import 'package:drift/drift.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/data/database/app_database.dart' as db;

class GroupMapper {
  const GroupMapper();

  Group toEntity(db.Group row) => Group(
        id: row.id,
        name: row.name,
        emoji: row.emoji,
        colorValue: row.colorValue,
        currencyCode: row.currencyCode,
        isArchived: row.isArchived,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

  db.GroupsCompanion toCompanion(Group entity) => db.GroupsCompanion(
        id: Value(entity.id),
        name: Value(entity.name),
        emoji: Value(entity.emoji),
        colorValue: Value(entity.colorValue),
        currencyCode: Value(entity.currencyCode),
        isArchived: Value(entity.isArchived),
        createdAt: Value(entity.createdAt),
        updatedAt: Value(entity.updatedAt),
      );
}
