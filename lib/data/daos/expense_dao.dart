import 'package:drift/drift.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/models/expense_split_table.dart';
import 'package:simsplit/data/models/expense_table.dart';

part 'expense_dao.g.dart';

@DriftAccessor(tables: [Expenses, ExpenseSplits])
class ExpenseDao extends DatabaseAccessor<AppDatabase> with _$ExpenseDaoMixin {
  ExpenseDao(super.db);

  /// Streams non-deleted expenses for a group, newest first.
  Stream<List<Expense>> watchExpensesByGroup(String groupId) =>
      (select(expenses)
            ..where(
                (e) => e.groupId.equals(groupId) & e.isDeleted.equals(false))
            ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]))
          .watch();

  /// Streams non-deleted expenses for a group together with their splits,
  /// newest first. Uses a single LEFT JOIN so the stream re-emits whenever
  /// either the expenses or the splits table changes, and every emission is
  /// a consistent snapshot of both.
  Stream<List<(Expense, List<ExpenseSplit>)>> watchExpensesWithSplitsByGroup(
      String groupId) {
    final query = select(expenses).join([
      leftOuterJoin(
          expenseSplits, expenseSplits.expenseId.equalsExp(expenses.id)),
    ])
      ..where(
          expenses.groupId.equals(groupId) & expenses.isDeleted.equals(false))
      ..orderBy([
        OrderingTerm.desc(expenses.expenseDate),
        OrderingTerm.asc(expenses.id),
        OrderingTerm.asc(expenseSplits.rowId),
      ]);

    return query.watch().map((rows) {
      final byId = <String, (Expense, List<ExpenseSplit>)>{};
      for (final row in rows) {
        final expense = row.readTable(expenses);
        final entry = byId.putIfAbsent(expense.id, () => (expense, []));
        final split = row.readTableOrNull(expenseSplits);
        if (split != null) entry.$2.add(split);
      }
      return byId.values.toList();
    });
  }

  Future<Expense?> getExpenseById(String id) =>
      (select(expenses)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<void> insertExpense(ExpensesCompanion companion) =>
      into(expenses).insert(companion);

  /// Writes only the columns present in [companion].
  Future<bool> updateExpenseById(ExpensesCompanion companion) async =>
      await (update(expenses)..where((e) => e.id.equals(companion.id.value)))
          .write(companion) >
      0;

  /// Soft-delete: sets isDeleted = true.
  Future<int> softDeleteExpense(String id, {String? updatedBy}) =>
      (update(expenses)..where((e) => e.id.equals(id))).write(
        ExpensesCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
          updatedBy: Value(updatedBy),
        ),
      );
}
