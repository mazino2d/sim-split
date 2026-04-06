import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../models/expense_table.dart';

part 'expense_dao.g.dart';

@DriftAccessor(tables: [Expenses])
class ExpenseDao extends DatabaseAccessor<AppDatabase> with _$ExpenseDaoMixin {
  ExpenseDao(super.db);

  /// Streams non-deleted expenses for a group, newest first.
  Stream<List<Expense>> watchExpensesByGroup(String groupId) =>
      (select(expenses)
            ..where((e) =>
                e.groupId.equals(groupId) & e.isDeleted.equals(false))
            ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]))
          .watch();

  Future<Expense?> getExpenseById(String id) =>
      (select(expenses)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<void> insertExpense(ExpensesCompanion companion) =>
      into(expenses).insert(companion);

  Future<bool> updateExpenseById(ExpensesCompanion companion) =>
      update(expenses).replace(companion);

  /// Soft-delete: sets isDeleted = true.
  Future<int> softDeleteExpense(String id) => (update(expenses)
        ..where((e) => e.id.equals(id)))
      .write(ExpensesCompanion(isDeleted: const Value(true)));
}
