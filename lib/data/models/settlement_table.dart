import 'package:drift/drift.dart';

import 'group_table.dart';
import 'member_table.dart';

class Settlements extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get fromMemberId =>
      text().references(Members, #id)();
  TextColumn get toMemberId =>
      text().references(Members, #id)();
  IntColumn get amountCents => integer()();
  TextColumn get currencyCode => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get settledAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
