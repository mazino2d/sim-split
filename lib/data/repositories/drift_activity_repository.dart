import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:simsplit/data/daos/sync_dao.dart';
import 'package:simsplit/data/database/app_database.dart' as db;
import 'package:simsplit/data/utils/stream_failure_transformer.dart';
import 'package:simsplit/domain/entities/activity_entry.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/activity_repository.dart';

/// Activity from Drift: entries recorded on this device and entries pulled
/// from the cloud share one table (R-3).
class DriftActivityRepository implements ActivityRepository {
  const DriftActivityRepository({required SyncDao syncDao})
      : _syncDao = syncDao;

  final SyncDao _syncDao;

  @override
  Stream<Either<Failure, List<ActivityEntry>>> watchActivity(String groupId) =>
      _syncDao
          .watchGroupActivity(groupId)
          .map((rows) => right<Failure, List<ActivityEntry>>([
                for (final (row, pending) in rows)
                  if (_toEntity(row, synced: !pending) case final entry?) entry,
              ]))
          .mapErrorsToDbFailure();

  /// Null for an entry this version does not know how to show.
  static ActivityEntry? _toEntity(db.Activity row, {required bool synced}) {
    final action = ActivityAction.values.asNameMap()[row.action];
    final type = ActivityEntityType.values.asNameMap()[row.entityType];
    if (action == null || type == null) return null;
    return ActivityEntry(
      id: row.id,
      groupId: row.groupId,
      actorUid: row.actorUid,
      action: action,
      entityType: type,
      entityId: row.entityId,
      before: row.before == null
          ? null
          : jsonDecode(row.before!) as Map<String, Object?>,
      after: jsonDecode(row.after) as Map<String, Object?>,
      clientTime: row.clientTime,
      synced: synced,
    );
  }
}
