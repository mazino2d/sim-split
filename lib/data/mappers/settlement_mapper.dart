import 'package:drift/drift.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/data/database/app_database.dart' as db;

class SettlementMapper {
  const SettlementMapper();

  Settlement toEntity(db.Settlement row) => Settlement(
        id: row.id,
        groupId: row.groupId,
        fromMemberId: row.fromMemberId,
        toMemberId: row.toMemberId,
        amountCents: row.amountCents,
        currencyCode: row.currencyCode,
        note: row.note,
        settledAt: row.settledAt,
        createdAt: row.createdAt,
      );

  db.SettlementsCompanion toCompanion(Settlement entity) =>
      db.SettlementsCompanion(
        id: Value(entity.id),
        groupId: Value(entity.groupId),
        fromMemberId: Value(entity.fromMemberId),
        toMemberId: Value(entity.toMemberId),
        amountCents: Value(entity.amountCents),
        currencyCode: Value(entity.currencyCode),
        note: Value(entity.note),
        settledAt: Value(entity.settledAt),
        createdAt: Value(entity.createdAt),
      );
}
