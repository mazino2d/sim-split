import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:simsplit/data/daos/sync_dao.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/sync/sync_codec.dart';
import 'package:uuid/uuid.dart';

/// Returns the signed-in account's uid, or null when signed out or when the
/// platform has no accounts (web, desktop).
typedef CurrentUid = String? Function();

/// Records local changes for sync: each change gets an activity entry (who,
/// when, before → after) and an outbox entry, written in the caller's Drift
/// transaction so a change is never stored without them (AC16, AC29).
///
/// Nothing is recorded while signed out: that data is uploaded as a whole on
/// first sign-in instead (AC7).
class SyncRecorder {
  SyncRecorder({
    required SyncDao syncDao,
    required CurrentUid currentUid,
    DateTime Function()? clock,
    String Function()? newId,
  })  : _syncDao = syncDao,
        _currentUid = currentUid,
        _clock = clock ?? DateTime.now,
        _newId = newId ?? const Uuid().v4;

  final SyncDao _syncDao;
  final CurrentUid _currentUid;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// The account changes are attributed to, or null when not recording.
  String? get uid => _currentUid();

  Future<void> record({
    required String groupId,
    required SyncEntity entity,
    required String entityId,
    required SyncAction action,
    Map<String, Object?>? before,
    required Map<String, Object?> after,
  }) async {
    final actor = uid;
    if (actor == null) return;
    if (action == SyncAction.update &&
        before != null &&
        const SyncCodec().sameContent(before, after)) {
      return;
    }
    await _syncDao.enqueue(ActivitiesCompanion.insert(
      id: _newId(),
      groupId: groupId,
      actorUid: actor,
      action: action.name,
      entityType: entity.name,
      entityId: entityId,
      before: Value(before == null ? null : jsonEncode(before)),
      after: jsonEncode(after),
      clientTime: _clock(),
    ));
  }
}
