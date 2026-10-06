import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show Value;
import 'package:fpdart/fpdart.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/sync/group_leaver.dart';
import 'package:simsplit/data/sync/sync_recorder.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/invite_failure.dart';
import 'package:simsplit/domain/failures/sync_failure.dart';
import 'package:simsplit/domain/repositories/invite_repository.dart';
import 'package:uuid/uuid.dart';

/// 18 random bytes, base64url: 24 characters that cannot be guessed.
String _randomToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return base64Url.encode(bytes);
}

/// Invite links on Firestore (AC9–AC14). A group's current token is stored
/// on the group (`inviteToken`) and as `invites/{token}` → `{groupId}`, which
/// anyone signed in can read by token. Joining adds the account to the
/// group's `memberUids`, proving the token as `joinToken`; security rules
/// check it against the current token.
class FirestoreInviteRepository implements InviteRepository {
  FirestoreInviteRepository({
    required AppDatabase database,
    required FirebaseFirestore firestore,
    required CurrentUid currentUid,
    required this.linkBase,
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? clock,
    String Function()? newId,
    String Function()? newToken,
  })  : _db = database,
        _firestore = firestore,
        _currentUid = currentUid,
        _clock = clock ?? DateTime.now,
        _newId = newId ?? const Uuid().v4,
        _newToken = newToken ?? _randomToken;

  /// Links are `<linkBase>/<token>`.
  final Uri linkBase;

  /// How long a cloud request may take before it counts as offline.
  final Duration timeout;

  final AppDatabase _db;
  final FirebaseFirestore _firestore;
  final CurrentUid _currentUid;
  final DateTime Function() _clock;
  final String Function() _newId;
  final String Function() _newToken;

  Uri _link(String token) =>
      linkBase.replace(pathSegments: [...linkBase.pathSegments, token]);

  DocumentReference<Map<String, dynamic>> _group(String groupId) =>
      _firestore.collection('groups').doc(groupId);

  @override
  Future<Either<Failure, Uri>> inviteLink(String groupId) async {
    final local = await _db.groupDao.getGroupById(groupId);
    final known = local?.inviteToken;
    if (known != null) return right(_link(known));
    return _guard(() async {
      // A group the server does not have yet cannot be shared.
      if (await _hasPendingChanges(groupId)) {
        return left(const SyncFailure.unsyncedChanges(1));
      }
      final current = (await _group(groupId).get().timeout(timeout))
          .data()?['inviteToken'] as String?;
      final token = current ?? await _replaceToken(groupId, previous: null);
      await _storeToken(groupId, token);
      return right(_link(token));
    });
  }

  @override
  Future<Either<Failure, Uri>> resetInviteLink(String groupId) =>
      _guard(() async {
        final previous = (await _group(groupId).get().timeout(timeout))
            .data()?['inviteToken'] as String?;
        final token = await _replaceToken(groupId, previous: previous);
        await _storeToken(groupId, token);
        return right(_link(token));
      });

  /// Writes a new token to the group with its invite document, and removes
  /// the [previous] one.
  Future<String> _replaceToken(String groupId, {String? previous}) async {
    final uid = _currentUid()!;
    final token = _newToken();
    final batch = _firestore.batch()
      ..update(_group(groupId), {
        'inviteToken': token,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      })
      ..set(_firestore.doc('invites/$token'), {'groupId': groupId});
    if (previous != null) batch.delete(_firestore.doc('invites/$previous'));
    await batch.commit().timeout(timeout);
    return token;
  }

  Future<void> _storeToken(String groupId, String token) =>
      (_db.update(_db.groups)..where((g) => g.id.equals(groupId)))
          .write(GroupsCompanion(inviteToken: Value(token)));

  @override
  Future<Either<Failure, String>> joinGroup(String token) => _guard(() async {
        final uid = _currentUid()!;
        final invite =
            await _firestore.doc('invites/$token').get().timeout(timeout);
        final groupId = invite.data()?['groupId'] as String?;
        if (groupId == null) return left(const InviteFailure.invalidLink());
        // Already in the group (pulled to this device): nothing to do.
        if (await _db.groupDao.getGroupById(groupId) != null) {
          return right(groupId);
        }

        final batch = _firestore.batch()
          ..update(_group(groupId), {
            'memberUids': FieldValue.arrayUnion([uid]),
            'joinToken': token,
            'updatedBy': uid,
            'updatedAt': FieldValue.serverTimestamp(),
          })
          ..set(_group(groupId).collection('activity').doc(_newId()), {
            'actorUid': uid,
            'action': 'join',
            'entityType': 'group',
            'entityId': groupId,
            'before': null,
            'after': <String, Object?>{},
            'clientTime': _clock().millisecondsSinceEpoch,
            'syncedAt': FieldValue.serverTimestamp(),
          });
        try {
          await batch.commit().timeout(timeout);
        } on FirebaseException catch (e) {
          // Rejected: the link was reset after this device read it, or the
          // account is already a member elsewhere.
          if (e.code != 'permission-denied') rethrow;
          final group = await _group(groupId).get().timeout(timeout);
          return group.exists
              ? right(groupId)
              : left(const InviteFailure.invalidLink());
        }
        return right(groupId);
      });

  @override
  Future<Either<Failure, Unit>> leaveGroup(String groupId) => _guard(() async {
        final uid = _currentUid()!;
        if (await _hasPendingChanges(groupId)) {
          return left(const SyncFailure.unsyncedChanges(1));
        }
        final group = await _group(groupId).get().timeout(timeout);
        await GroupLeaver(
          firestore: _firestore,
          timeout: timeout,
          clock: _clock,
          newId: _newId,
        ).leave(group, uid);
        // The pull listener then removes the group from this device.
        return right(unit);
      });

  Future<bool> _hasPendingChanges(String groupId) async =>
      (await _db.syncDao.watchPendingEntityIds(groupId: groupId).first)
          .isNotEmpty;

  /// Maps timeouts and backend errors to sync failures.
  Future<Either<Failure, T>> _guard<T>(
      Future<Either<Failure, T>> Function() run) async {
    try {
      return await run();
    } on TimeoutException {
      return left(const SyncFailure.noConnection());
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        return left(const SyncFailure.noConnection());
      }
      if (e.code == 'permission-denied' || e.code == 'not-found') {
        return left(const InviteFailure.invalidLink());
      }
      return left(SyncFailure.serverError('${e.code}: ${e.message}'));
    } catch (e) {
      return left(SyncFailure.serverError(e.toString()));
    }
  }
}
