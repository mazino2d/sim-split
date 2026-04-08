import 'package:drift/drift.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/data/database/app_database.dart' as db;

class ExpenseMapper {
  const ExpenseMapper();

  Expense toEntity(db.Expense row, List<db.ExpenseSplit> splitRows) => Expense(
        id: row.id,
        groupId: row.groupId,
        title: row.title,
        amountCents: row.amountCents,
        currencyCode: row.currencyCode,
        paidByMemberId: row.paidByMemberId,
        splitType: _splitTypeFromString(row.splitType),
        category: _categoryFromString(row.category),
        note: row.note,
        expenseDate: row.expenseDate,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        isDeleted: row.isDeleted,
        splits: splitRows.map(_splitToEntity).toList(),
      );

  ExpenseSplit _splitToEntity(db.ExpenseSplit row) => ExpenseSplit(
        id: row.id,
        expenseId: row.expenseId,
        memberId: row.memberId,
        value: row.value,
        amountCents: row.amountCents,
      );

  db.ExpensesCompanion toCompanion(Expense entity) => db.ExpensesCompanion(
        id: Value(entity.id),
        groupId: Value(entity.groupId),
        title: Value(entity.title),
        amountCents: Value(entity.amountCents),
        currencyCode: Value(entity.currencyCode),
        paidByMemberId: Value(entity.paidByMemberId),
        splitType: Value(_splitTypeToString(entity.splitType)),
        category: Value(_categoryToString(entity.category)),
        note: Value(entity.note),
        expenseDate: Value(entity.expenseDate),
        createdAt: Value(entity.createdAt),
        updatedAt: Value(entity.updatedAt),
        isDeleted: Value(entity.isDeleted),
      );

  List<db.ExpenseSplitsCompanion> splitCompanions(List<ExpenseSplit> splits) =>
      splits
          .map((s) => db.ExpenseSplitsCompanion(
                id: Value(s.id),
                expenseId: Value(s.expenseId),
                memberId: Value(s.memberId),
                value: Value(s.value),
                amountCents: Value(s.amountCents),
              ))
          .toList();

  SplitType _splitTypeFromString(String s) => switch (s) {
        'equal' => SplitType.equal,
        'percentage' => SplitType.percentage,
        'exact' => SplitType.exact,
        'shares' => SplitType.shares,
        _ => SplitType.equal,
      };

  String _splitTypeToString(SplitType t) => switch (t) {
        SplitType.equal => 'equal',
        SplitType.percentage => 'percentage',
        SplitType.exact => 'exact',
        SplitType.shares => 'shares',
      };

  ExpenseCategory _categoryFromString(String s) => switch (s) {
        'food' => ExpenseCategory.food,
        'transport' => ExpenseCategory.transport,
        'accommodation' => ExpenseCategory.accommodation,
        'entertainment' => ExpenseCategory.entertainment,
        'shopping' => ExpenseCategory.shopping,
        'health' => ExpenseCategory.health,
        _ => ExpenseCategory.other,
      };

  String _categoryToString(ExpenseCategory c) => switch (c) {
        ExpenseCategory.food => 'food',
        ExpenseCategory.transport => 'transport',
        ExpenseCategory.accommodation => 'accommodation',
        ExpenseCategory.entertainment => 'entertainment',
        ExpenseCategory.shopping => 'shopping',
        ExpenseCategory.health => 'health',
        ExpenseCategory.other => 'other',
      };
}
