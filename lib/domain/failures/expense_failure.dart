import 'package:simsplit/domain/failures/core_failure.dart';

sealed class ExpenseFailure extends Failure {
  const ExpenseFailure() : super();

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
  const factory ExpenseFailure.duplicateParticipant() = DuplicateParticipant;
  const factory ExpenseFailure.negativeSplitValue() = NegativeSplitValue;
}

final class ExpenseNotFound extends ExpenseFailure {
  const ExpenseNotFound() : super();
}

final class ExpenseMemberNotFound extends ExpenseFailure {
  const ExpenseMemberNotFound() : super();
}

final class InvalidSplitType extends ExpenseFailure {
  const InvalidSplitType() : super();
}

final class PercentageDoesNotSum extends ExpenseFailure {
  const PercentageDoesNotSum() : super();
}

final class ExactDoesNotSum extends ExpenseFailure {
  const ExactDoesNotSum() : super();
}

final class InvalidShares extends ExpenseFailure {
  const InvalidShares() : super();
}

final class NoParticipants extends ExpenseFailure {
  const NoParticipants() : super();
}

final class AmountMustBePositive extends ExpenseFailure {
  const AmountMustBePositive() : super();
}

/// The payer or a split participant does not belong to the expense's group.
final class ExpenseMemberNotInGroup extends ExpenseFailure {
  const ExpenseMemberNotInGroup() : super();
}

/// The expense title is empty or whitespace only.
final class ExpenseTitleEmpty extends ExpenseFailure {
  const ExpenseTitleEmpty() : super();
}

/// The same member appears more than once in the split inputs.
final class DuplicateParticipant extends ExpenseFailure {
  const DuplicateParticipant() : super();
}

/// A percentage or exact split value is negative.
final class NegativeSplitValue extends ExpenseFailure {
  const NegativeSplitValue() : super();
}
