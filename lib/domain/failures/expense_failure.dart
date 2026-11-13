import 'package:simsplit/domain/failures/core_failure.dart';

sealed class ExpenseFailure extends Failure {
  const ExpenseFailure(super.name);

  const factory ExpenseFailure.notFound() = ExpenseNotFound;
  const factory ExpenseFailure.memberNotFound() = ExpenseMemberNotFound;
  const factory ExpenseFailure.invalidSplitType() = InvalidSplitType;
  const factory ExpenseFailure.percentageDoesNotSumTo100() =
      PercentageDoesNotSum;
  const factory ExpenseFailure.exactDoesNotSumToTotal() = ExactDoesNotSum;
  const factory ExpenseFailure.invalidShares() = InvalidShares;
  const factory ExpenseFailure.noParticipants() = NoParticipants;
  const factory ExpenseFailure.amountMustBePositive() = AmountMustBePositive;
  const factory ExpenseFailure.memberNotInGroup() = ExpenseMemberNotInGroup;
  const factory ExpenseFailure.titleEmpty() = ExpenseTitleEmpty;
  const factory ExpenseFailure.titleTooLong() = ExpenseTitleTooLong;
  const factory ExpenseFailure.duplicateParticipant() = DuplicateParticipant;
  const factory ExpenseFailure.negativeSplitValue() = NegativeSplitValue;
}

final class ExpenseNotFound extends ExpenseFailure {
  const ExpenseNotFound() : super('expense_not_found');
}

final class ExpenseMemberNotFound extends ExpenseFailure {
  const ExpenseMemberNotFound() : super('expense_member_not_found');
}

final class InvalidSplitType extends ExpenseFailure {
  const InvalidSplitType() : super('invalid_split_type');
}

final class PercentageDoesNotSum extends ExpenseFailure {
  const PercentageDoesNotSum() : super('percentage_does_not_sum');
}

final class ExactDoesNotSum extends ExpenseFailure {
  const ExactDoesNotSum() : super('exact_does_not_sum');
}

final class InvalidShares extends ExpenseFailure {
  const InvalidShares() : super('invalid_shares');
}

final class NoParticipants extends ExpenseFailure {
  const NoParticipants() : super('no_participants');
}

final class AmountMustBePositive extends ExpenseFailure {
  const AmountMustBePositive() : super('amount_must_be_positive');
}

/// The payer or a split participant does not belong to the expense's group.
final class ExpenseMemberNotInGroup extends ExpenseFailure {
  const ExpenseMemberNotInGroup() : super('expense_member_not_in_group');
}

/// The expense title is empty or whitespace only.
final class ExpenseTitleEmpty extends ExpenseFailure {
  const ExpenseTitleEmpty() : super('expense_title_empty');
}

/// The expense title is longer than `maxExpenseTitleLength`.
final class ExpenseTitleTooLong extends ExpenseFailure {
  const ExpenseTitleTooLong() : super('expense_title_too_long');
}

/// The same member appears more than once in the split inputs.
final class DuplicateParticipant extends ExpenseFailure {
  const DuplicateParticipant() : super('duplicate_participant');
}

/// A percentage or exact split value is negative.
final class NegativeSplitValue extends ExpenseFailure {
  const NegativeSplitValue() : super('negative_split_value');
}
