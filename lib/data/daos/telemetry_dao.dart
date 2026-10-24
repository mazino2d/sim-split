import 'package:drift/drift.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/models/telemetry_table.dart';

part 'telemetry_dao.g.dart';

@DriftAccessor(tables: [TelemetryQueue])
class TelemetryDao extends DatabaseAccessor<AppDatabase>
    with _$TelemetryDaoMixin {
  TelemetryDao(super.db);

  /// Queues an item and drops the oldest of its kind beyond [max].
  Future<int> enqueue(String kind, String payload, {required int max}) =>
      transaction(() async {
        final id = await into(telemetryQueue).insert(
          TelemetryQueueCompanion.insert(
            kind: kind,
            payload: payload,
            createdAt: DateTime.now(),
          ),
        );
        final keep = await (select(telemetryQueue)
              ..where((t) => t.kind.equals(kind))
              ..orderBy([(t) => OrderingTerm.desc(t.id)])
              ..limit(max))
            .map((t) => t.id)
            .get();
        await (delete(telemetryQueue)
              ..where((t) => t.kind.equals(kind) & t.id.isNotIn(keep)))
            .go();
        return id;
      });

  /// Rewrites a queued item; a no-op once it has been sent.
  Future<void> updatePayload(int id, String payload) =>
      (update(telemetryQueue)..where((t) => t.id.equals(id)))
          .write(TelemetryQueueCompanion(payload: Value(payload)));

  /// The oldest queued items of a kind, in order.
  Future<List<TelemetryQueueData>> oldest(String kind, int limit) =>
      (select(telemetryQueue)
            ..where((t) => t.kind.equals(kind))
            ..orderBy([(t) => OrderingTerm.asc(t.id)])
            ..limit(limit))
          .get();

  Future<void> deleteIds(Iterable<int> ids) =>
      (delete(telemetryQueue)..where((t) => t.id.isIn(ids))).go();

  Future<void> clear(String kind) =>
      (delete(telemetryQueue)..where((t) => t.kind.equals(kind))).go();

  Stream<int> watchCount(String kind) {
    final count = telemetryQueue.id.count();
    return (selectOnly(telemetryQueue)
          ..addColumns([count])
          ..where(telemetryQueue.kind.equals(kind)))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }
}
