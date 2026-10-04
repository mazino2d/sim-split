import 'package:drift/drift.dart';

import 'package:simsplit/data/models/group_table.dart';
import 'package:simsplit/data/models/member_table.dart';

class Settlements extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get fromMemberId => text().references(Members, #id)();
  TextColumn get toMemberId => text().references(Members, #id)();
  IntColumn get amountCents => integer()();
  TextColumn get currencyCode => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get settledAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  /// Account uid that created / last changed the row (R-3). Null for rows
  /// written while signed out (v1 data, web).
  TextColumn get createdBy => text().nullable()();
  TextColumn get updatedBy => text().nullable()();

  /// Tombstone (R-3): deletions are soft so they can sync.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
