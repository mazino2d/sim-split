import 'package:drift/drift.dart';

import 'package:simsplit/data/models/expense_table.dart';
import 'package:simsplit/data/models/member_table.dart';

class ExpenseSplits extends Table {
  TextColumn get id => text()();
  TextColumn get expenseId =>
      text().references(Expenses, #id, onDelete: KeyAction.cascade)();
  TextColumn get memberId => text().references(Members, #id)();

  /// Raw input value (meaning depends on splitType — see ExpenseSplit entity).
  IntColumn get value => integer()();

  /// Resolved amount in cents for this member. Always stored for auditability.
  IntColumn get amountCents => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
