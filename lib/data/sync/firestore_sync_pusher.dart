import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simsplit/data/daos/sync_dao.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/sync/sync_codec.dart';

/// Drains the outbox to Firestore, oldest change first (AC16, AC18b).
///
/// Each change is written together with its activity entry in one batch, so
/// a change never reaches the server without its history (AC29). The
/// Firestore offline cache is disabled (Drift is the cache), so a commit
/// made offline simply waits until the connection is back; if the app is
/// killed meanwhile, the outbox still holds the change and it is pushed
/// again on the next start.
class FirestoreSyncPusher {
  FirestoreSyncPusher({
    required SyncDao syncDao,
    required FirebaseFirestore firestore,
    this.batchSize = 200,
    Duration Function(int attempt)? retryDelay,
  })  : _syncDao = syncDao,
        _firestore = firestore,
        _retryDelay = retryDelay ?? _defaultRetryDelay;

  /// Changes per Firestore batch. Each change is two writes and a batch
  /// holds at most 500.
  final int batchSize;

  final SyncDao _syncDao;
  final FirebaseFirestore _firestore;
  final Duration Function(int attempt) _retryDelay;

  StreamSubscription<int>? _pending;
  Future<void>? _draining;
  bool _again = false;
  Timer? _retry;
  int _attempt = 0;

  static Duration _defaultRetryDelay(int attempt) =>
      Duration(seconds: (5 * (1 << attempt.clamp(0, 6))).clamp(5, 300));

  /// Codes for which retrying the same write can never succeed.
  static const _permanentCodes = {
    'permission-denied',
    'invalid-argument',
    'failed-precondition',
    'not-found',
    'already-exists',
    'out-of-range',
  };

  bool get isRunning => _pending != null;

  /// Pushes now and whenever new changes are queued.
  void start() {
    _pending ??= _syncDao.watchPendingCount().listen((pending) {
      if (pending > 0) _kick();
    });
  }

  /// Stops pushing after the batch in flight, without waiting for it (an
  /// offline commit only completes once the connection is back). Queued
  /// changes stay queued.
  Future<void> stop() async {
    _retry?.cancel();
    _retry = null;
    final cancelled = _pending?.cancel();
    _pending = null;
    await cancelled;
  }

  /// Completes once the drain in progress (if any) is done. For tests.
  Future<void> idle() async {
    while (_draining != null) {
      await _draining;
    }
  }

  void _kick() {
    if (_draining != null) {
      _again = true;
      return;
    }
    _draining = _drain().whenComplete(() {
      _draining = null;
      if (_again && isRunning) {
        _again = false;
        _kick();
      }
    });
  }

  Future<void> _drain() async {
    try {
      while (isRunning) {
        final batch = await _syncDao.nextBatch(batchSize);
        if (batch.isEmpty) break;
        await _push(batch);
      }
      _attempt = 0;
    } catch (_) {
      // Network or server trouble: try again later, oldest change first.
      if (!isRunning) return;
      _retry?.cancel();
      _retry = Timer(_retryDelay(_attempt++), _kick);
    }
  }

  Future<void> _push(List<(OutboxEntry, Activity)> batch) async {
    try {
      await _commit(batch);
      await _syncDao.removeEntries(batch.map((e) => e.$1.seq));
    } on FirebaseException catch (e) {
      if (!_permanentCodes.contains(e.code)) rethrow;
      await _resolveRejected(batch);
    }
  }

  /// A rejected batch either was committed before (the app stopped before
  /// the outbox was cleared, and activity entries can only be created once)
  /// or holds a change the server will never accept. Drops what is already
  /// on the server; otherwise sets the oldest change aside so the rest can
  /// go through.
  Future<void> _resolveRejected(List<(OutboxEntry, Activity)> batch) async {
    final pushed = <int>[];
    for (final (entry, activity) in batch) {
      final doc = await _activityRef(activity).get();
      if (doc.exists) pushed.add(entry.seq);
    }
    if (pushed.isNotEmpty) {
      await _syncDao.removeEntries(pushed);
    } else {
      await _syncDao.markFailed([batch.first.$1.seq]);
    }
  }

  Future<void> _commit(List<(OutboxEntry, Activity)> batch) {
    final writes = _firestore.batch();
    for (final (_, activity) in batch) {
      final entity = SyncEntity.values.byName(activity.entityType);
      final action = SyncAction.values.byName(activity.action);
      final after = jsonDecode(activity.after) as Map<String, Object?>;
      final before = activity.before == null
          ? null
          : jsonDecode(activity.before!) as Map<String, Object?>;

      final data = {...after}
        ..remove('id')
        ..['updatedBy'] = activity.actorUid
        ..['updatedAt'] = FieldValue.serverTimestamp();
      if (entity == SyncEntity.group && action == SyncAction.create) {
        data['ownerUid'] = activity.actorUid;
        data['memberUids'] = [activity.actorUid];
      }
      // Merge keeps fields this device does not own (the group's members
      // and owner); every synced field is always sent in full.
      writes.set(_entityRef(activity, entity), data, SetOptions(merge: true));

      writes.set(_activityRef(activity), {
        'actorUid': activity.actorUid,
        'action': activity.action,
        'entityType': activity.entityType,
        'entityId': activity.entityId,
        'before': before,
        'after': after,
        'clientTime': activity.clientTime.millisecondsSinceEpoch,
        'syncedAt': FieldValue.serverTimestamp(),
      });
    }
    return writes.commit();
  }

  DocumentReference<Map<String, dynamic>> _groupRef(String groupId) =>
      _firestore.collection('groups').doc(groupId);

  DocumentReference<Map<String, dynamic>> _entityRef(
      Activity activity, SyncEntity entity) {
    final group = _groupRef(activity.groupId);
    final collection = entity.collection;
    return collection == null
        ? group
        : group.collection(collection).doc(activity.entityId);
  }

  DocumentReference<Map<String, dynamic>> _activityRef(Activity activity) =>
      _groupRef(activity.groupId).collection('activity').doc(activity.id);
}
