import 'package:drift/drift.dart';

/// One entry of a group's activity history (R-3, AC25–AC30). Local changes
/// are recorded here and pushed to Firestore together with the change.
class Activities extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text()();
  TextColumn get actorUid => text()();

  /// 'create' | 'update' | 'delete'
  TextColumn get action => text()();

  /// 'group' | 'member' | 'expense' | 'settlement'
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  /// JSON snapshots of the record before and after the change (see
  /// SyncCodec). `before` is null for a create.
  TextColumn get before => text().nullable()();
  TextColumn get after => text()();

  /// Device time of the change (AC29).
  DateTimeColumn get clientTime => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Changes waiting to be pushed, in the order they were made (AC16, AC18b).
class OutboxEntries extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get groupId => text()();
  TextColumn get activityId => text()();

  /// Set when the server rejected the change for good (e.g. permission
  /// denied). Failed entries are skipped so they never block the queue.
  BoolColumn get failed => boolean().withDefault(const Constant(false))();
}

/// Small key-value store for sync bookkeeping (e.g. which account the local
/// data was uploaded to).
class SyncStates extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
