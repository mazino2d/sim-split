import 'package:drift/drift.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/models/sync_tables.dart';

part 'sync_dao.g.dart';

@DriftAccessor(tables: [Activities, OutboxEntries, SyncStates])
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  /// Records a change: its activity entry plus an outbox entry pointing at
  /// it. Call inside the transaction that writes the change.
  Future<void> enqueue(ActivitiesCompanion activity) async {
    await into(activities).insert(activity);
    await into(outboxEntries).insert(OutboxEntriesCompanion.insert(
      groupId: activity.groupId.value,
      activityId: activity.id.value,
    ));
  }

  /// Number of changes still waiting to be pushed (failed ones excluded).
  Stream<int> watchPendingCount() {
    final count = outboxEntries.seq.count();
    return (selectOnly(outboxEntries)
          ..addColumns([count])
          ..where(outboxEntries.failed.equals(false)))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  Future<int> pendingCount() => watchPendingCount().first;

  /// The oldest pending changes, all from the same group (one Firestore
  /// batch must stay within one group's security-rule lookups), in order.
  Future<List<(OutboxEntry, Activity)>> nextBatch(int limit) async {
    final first = await (select(outboxEntries)
          ..where((o) => o.failed.equals(false))
          ..orderBy([(o) => OrderingTerm.asc(o.seq)])
          ..limit(1))
        .getSingleOrNull();
    if (first == null) return const [];

    // Stop at the first entry of another group so order is kept across
    // groups too.
    final next = await (select(outboxEntries)
          ..where((o) =>
              o.failed.equals(false) &
              o.seq.isBiggerOrEqualValue(first.seq) &
              o.groupId.equals(first.groupId).not())
          ..orderBy([(o) => OrderingTerm.asc(o.seq)])
          ..limit(1))
        .getSingleOrNull();

    final query = select(outboxEntries).join([
      innerJoin(activities, activities.id.equalsExp(outboxEntries.activityId)),
    ])
      ..where(outboxEntries.failed.equals(false) &
          outboxEntries.seq.isBiggerOrEqualValue(first.seq) &
          (next == null
              ? const Constant(true)
              : outboxEntries.seq.isSmallerThanValue(next.seq)))
      ..orderBy([OrderingTerm.asc(outboxEntries.seq)])
      ..limit(limit);
    final rows = await query.get();
    return [
      for (final row in rows)
        (row.readTable(outboxEntries), row.readTable(activities)),
    ];
  }

  Future<void> removeEntries(Iterable<int> seqs) =>
      (delete(outboxEntries)..where((o) => o.seq.isIn(seqs))).go();

  Future<void> markFailed(Iterable<int> seqs) =>
      (update(outboxEntries)..where((o) => o.seq.isIn(seqs)))
          .write(const OutboxEntriesCompanion(failed: Value(true)));

  Future<String?> readState(String key) async =>
      (await (select(syncStates)..where((s) => s.key.equals(key)))
              .getSingleOrNull())
          ?.value;

  Future<void> writeState(String key, String value) =>
      into(syncStates).insertOnConflictUpdate(
          SyncStatesCompanion.insert(key: key, value: value));
}
