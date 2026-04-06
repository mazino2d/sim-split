import 'package:drift/drift.dart';

import 'group_table.dart';
import 'member_table.dart';

class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  /// Amount in integer cents (VND × 100 for schema uniformity). Never use float.
  IntColumn get amountCents => integer()();
  TextColumn get currencyCode => text()();
  TextColumn get paidByMemberId =>
      text().references(Members, #id)();
  TextColumn get splitType => text()(); // 'equal' | 'percentage' | 'exact' | 'shares'
  TextColumn get category => text().withDefault(const Constant('other'))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get expenseDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
