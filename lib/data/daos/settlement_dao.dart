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
            ..where((s) => s.groupId.equals(groupId))
            ..orderBy([(s) => OrderingTerm.desc(s.settledAt)]))
          .watch();

  Future<void> insertSettlement(SettlementsCompanion companion) =>
      into(settlements).insert(companion);

  Future<int> deleteSettlementById(String id) =>
      (delete(settlements)..where((s) => s.id.equals(id))).go();
}
