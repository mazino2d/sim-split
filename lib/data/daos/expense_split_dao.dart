import 'package:drift/drift.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/models/expense_split_table.dart';

part 'expense_split_dao.g.dart';

@DriftAccessor(tables: [ExpenseSplits])
class ExpenseSplitDao extends DatabaseAccessor<AppDatabase>
    with _$ExpenseSplitDaoMixin {
  ExpenseSplitDao(super.db);

  Future<List<ExpenseSplit>> getSplitsForExpense(String expenseId) =>
      (select(expenseSplits)..where((s) => s.expenseId.equals(expenseId)))
          .get();

  Future<void> insertSplits(List<ExpenseSplitsCompanion> companions) =>
      batch((b) => b.insertAll(expenseSplits, companions));

  Future<int> deleteSplitsForExpense(String expenseId) =>
      (delete(expenseSplits)..where((s) => s.expenseId.equals(expenseId))).go();
}
