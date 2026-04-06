import 'package:freezed_annotation/freezed_annotation.dart';
import 'expense_split.dart';

part 'expense.freezed.dart';

/// Expense categories shown in UI.
enum ExpenseCategory {
  food,
  transport,
  accommodation,
  entertainment,
  shopping,
  health,
  other,
}

@freezed
class Expense with _$Expense {
  const factory Expense({
    required String id,
    required String groupId,
    required String title,
    /// Total amount in cents (integer to avoid floating-point errors).
    required int amountCents,
    required String currencyCode,
    required String paidByMemberId,
    required SplitType splitType,
    @Default(ExpenseCategory.other) ExpenseCategory category,
    String? note,
    required DateTime expenseDate,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(false) bool isDeleted,
    @Default([]) List<ExpenseSplit> splits,
  }) = _Expense;
}
