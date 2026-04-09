import 'package:freezed_annotation/freezed_annotation.dart';

part 'expense_split.freezed.dart';

/// How to split an expense among participants.
enum SplitType { equal, percentage, exact, shares }

@freezed
sealed class ExpenseSplit with _$ExpenseSplit {
  const factory ExpenseSplit({
    required String id,
    required String expenseId,
    required String memberId,

    /// Raw input value:
    /// - equal: pre-computed amountCents / N
    /// - percentage: scaled integer (33.33% → 3333)
    /// - exact: amountCents assigned to this member
    /// - shares: number of shares (positive integer)
    required int value,

    /// Always the resolved amount in cents for this member.
    required int amountCents,
  }) = _ExpenseSplit;
}
