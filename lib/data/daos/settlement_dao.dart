import 'package:drift/drift.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/models/settlement_table.dart';

part 'settlement_dao.g.dart';

@DriftAccessor(tables: [Settlements])
class SettlementDao extends DatabaseAccessor<AppDatabase>
    with _$SettlementDaoMixin {
  SettlementDao(super.db);

  Stream<List<Settlement>> watchSettlementsByGroup(String groupId) =>
      (select(settlements)
            ..where((s) => s.groupId.equals(groupId) & s.deleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.settledAt)]))
          .watch();

  Future<void> insertSettlement(SettlementsCompanion companion) =>
      into(settlements).insert(companion);

  Future<Settlement?> getSettlementById(String id) =>
      (select(settlements)..where((s) => s.id.equals(id))).getSingleOrNull();

  /// Soft-delete: marks the settlement as a tombstone so the deletion can
  /// sync.
  Future<int> softDeleteSettlement(String id, {String? updatedBy}) =>
      (update(settlements)..where((s) => s.id.equals(id))).write(
        SettlementsCompanion(
          deleted: const Value(true),
          updatedBy: Value(updatedBy),
        ),
      );
}
