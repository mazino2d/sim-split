import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fpdart/fpdart.dart';
import 'package:simsplit/data/daos/sync_dao.dart';
import 'package:simsplit/data/sync/firestore_sync_puller.dart';
import 'package:simsplit/data/sync/firestore_sync_pusher.dart';
import 'package:simsplit/data/sync/group_leaver.dart';
import 'package:simsplit/data/sync/local_data_uploader.dart';
import 'package:simsplit/data/sync/sync_recorder.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/sync_failure.dart';
import 'package:simsplit/domain/repositories/sync_repository.dart';
import 'package:uuid/uuid.dart';

class FirestoreSyncRepository implements SyncRepository {
  FirestoreSyncRepository({
    required SyncDao syncDao,
    required LocalDataUploader uploader,
    required FirestoreSyncPusher pusher,
    required FirestoreSyncPuller puller,
    required FirebaseFirestore firestore,
    required CurrentUid currentUid,
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? clock,
    String Function()? newId,
  })  : _syncDao = syncDao,
        _uploader = uploader,
        _pusher = pusher,
        _puller = puller,
        _firestore = firestore,
        _currentUid = currentUid,
        _clock = clock ?? DateTime.now,
        _newId = newId ?? const Uuid().v4;

  /// How long a cloud request may take before it counts as offline.
  final Duration timeout;

  final SyncDao _syncDao;
  final LocalDataUploader _uploader;
  final FirestoreSyncPusher _pusher;
  final FirestoreSyncPuller _puller;
  final FirebaseFirestore _firestore;
  final CurrentUid _currentUid;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Firestore's limit is 500 writes per batch.
  static const _deleteBatchSize = 400;

  @override
  Future<Either<Failure, Unit>> start(AuthUser user) async {
    try {
      await _uploader.upload(user.uid);
      _pusher.start();
      _puller.start(user.uid);
      return right(unit);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> stop() async {
    await _pusher.stop();
    await _puller.stop();
    return right(unit);
  }

  @override
  Stream<Either<Failure, Set<String>>> watchUnsyncedRecordIds(String groupId) =>
      _syncDao
          .watchPendingEntityIds(groupId: groupId)
          .map(right<Failure, Set<String>>);

  @override
  Future<Either<Failure, int>> pendingChangeCount() async {
    try {
      return right(await _syncDao.pendingCount());
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteCloudData() async {
    final uid = _currentUid();
    if (uid == null) return right(unit);

    // Pushing into a group while leaving or deleting it would undo the
    // cleanup, so pushing pauses and resumes only if the cleanup fails.
    final wasRunning = _pusher.isRunning;
    await _pusher.stop();
    try {
      final groups = await _firestore
          .collection('groups')
          .where('memberUids', arrayContains: uid)
          .get()
          .timeout(timeout);
      for (final group in groups.docs) {
        final memberUids = List<String>.from(
            group.data()['memberUids'] as List? ?? const <String>[]);
        if (memberUids.length <= 1) {
          await _deleteGroup(group);
        } else {
          await GroupLeaver(
            firestore: _firestore,
            timeout: timeout,
            clock: _clock,
            newId: _newId,
          ).leave(group, uid);
        }
      }
      return right(unit);
    } on TimeoutException {
      if (wasRunning) _pusher.start();
      return left(const SyncFailure.noConnection());
    } on FirebaseException catch (e) {
      if (wasRunning) _pusher.start();
      return left(e.code == 'unavailable'
          ? const SyncFailure.noConnection()
          : SyncFailure.serverError('${e.code}: ${e.message}'));
    } catch (e) {
      if (wasRunning) _pusher.start();
      return left(SyncFailure.serverError(e.toString()));
    }
  }

  /// Deletes a group whose only member is the account, history included.
  /// Subcollections go first: security rules check membership on the group
  /// document.
  Future<void> _deleteGroup(
      DocumentSnapshot<Map<String, dynamic>> snapshot) async {
    final group = snapshot.reference;
    // The invite link goes first too: removing it checks the owner on the
    // group document.
    final token = snapshot.data()?['inviteToken'] as String?;
    if (token != null) {
      await _firestore.doc('invites/$token').delete().timeout(timeout);
    }
    for (final name in ['members', 'expenses', 'settlements', 'activity']) {
      while (true) {
        final docs = await group
            .collection(name)
            .limit(_deleteBatchSize)
            .get()
            .timeout(timeout);
        if (docs.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in docs.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit().timeout(timeout);
      }
    }
    await group.delete().timeout(timeout);
  }
}
