import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/notification_prefs_repository.dart';

/// `users/{uid}.notificationPrefs` (R-9 AC3, AC4): `groupActivity`,
/// `settleReminder`, `updates` (bools; a missing one means the default in
/// `crm/categories.yaml`) and `mutedGroups` (group IDs). The rules let only
/// the account change it, with these keys and types.
class FirestoreNotificationPrefsRepository
    implements NotificationPrefsRepository {
  const FirestoreNotificationPrefsRepository({
    required FirebaseFirestore firestore,
    required String? Function() currentUid,
  })  : _firestore = firestore,
        _currentUid = currentUid;

  final FirebaseFirestore _firestore;
  final String? Function() _currentUid;

  static const field = 'notificationPrefs';

  /// A change made offline stays queued; the switch keeps its new state
  /// from the local snapshot and the write goes out once online.
  static const _ackTimeout = Duration(seconds: 5);

  static NotificationPrefs parse(Object? raw) {
    if (raw is! Map) return const NotificationPrefs();
    final muted = raw['mutedGroups'];
    return NotificationPrefs(
      categories: {
        for (final c in NotificationCategory.values)
          if (raw[c.prefKey] is bool) c: raw[c.prefKey] as bool,
      },
      mutedGroups:
          muted is List ? muted.whereType<String>().toList() : const [],
    );
  }

  @override
  Stream<Either<Failure, NotificationPrefs>> watchPrefs() {
    final uid = _currentUid();
    if (uid == null) return Stream.value(right(const NotificationPrefs()));
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map<Either<Failure, NotificationPrefs>>(
            (doc) => right(parse(doc.data()?[field])))
        .transform(StreamTransformer.fromHandlers(
          handleError: (error, stackTrace, sink) =>
              sink.add(left(Failure.unexpected(error.toString()))),
        ));
  }

  Future<Either<Failure, Unit>> _update(Map<String, Object> changes) async {
    final uid = _currentUid();
    if (uid == null) return left(const Failure.unexpected('Not signed in'));
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .update(changes)
          .timeout(_ackTimeout);
      return right(unit);
    } on TimeoutException {
      return right(unit);
    } on FirebaseException catch (e) {
      return left(Failure.unexpected('${e.code} ${e.message}'));
    }
  }

  @override
  Future<Either<Failure, Unit>> setCategory(
          NotificationCategory category, bool on) =>
      _update({'$field.${category.prefKey}': on});

  @override
  Future<Either<Failure, Unit>> setGroupMuted(String groupId, bool muted) =>
      _update({
        '$field.mutedGroups': muted
            ? FieldValue.arrayUnion([groupId])
            : FieldValue.arrayRemove([groupId]),
      });
}
