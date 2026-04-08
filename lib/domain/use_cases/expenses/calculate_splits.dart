import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/value_objects/unique_id.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Raw user input for a single participant's split entry.
class RawSplitInput {
  const RawSplitInput({required this.memberId, this.value = 0});

  final String memberId;

  /// Meaning depends on [SplitType]:
  /// - equal: ignored (computed from totalAmountCents / N)
  /// - percentage: scaled integer (33.33% → 3333)
  /// - exact: amountCents for this member
  /// - shares: number of shares (positive integer)
  final int value;
}

class CalculateSplitsParams {
  const CalculateSplitsParams({
    required this.expenseId,
    required this.totalAmountCents,
    required this.splitType,
    required this.inputs,
  });

  final String expenseId;
  final int totalAmountCents;
  final SplitType splitType;
  final List<RawSplitInput> inputs;
}

/// Pure domain use case — no repository dependencies.
/// Validates and computes [ExpenseSplit] list from raw user input.
class CalculateSplits
    implements UseCase<List<ExpenseSplit>, CalculateSplitsParams> {
  const CalculateSplits();

  @override
  Either<Failure, List<ExpenseSplit>> call(CalculateSplitsParams params) {
    if (params.inputs.isEmpty) {
      return left(const ExpenseFailure.noParticipants());
    }
    if (params.totalAmountCents <= 0) {
      return left(const ExpenseFailure.amountMustBePositive());
    }

    return switch (params.splitType) {
      SplitType.equal => _calculateEqual(params),
      SplitType.percentage => _calculatePercentage(params),
      SplitType.exact => _validateExact(params),
      SplitType.shares => _calculateShares(params),
    };
  }

  Either<Failure, List<ExpenseSplit>> _calculateEqual(
      CalculateSplitsParams params) {
    final n = params.inputs.length;
    final baseAmount = params.totalAmountCents ~/ n;
    final remainder = params.totalAmountCents % n;

    // Distribute remainder to first members (1 cent each) to avoid rounding loss
    return right([
      for (var i = 0; i < n; i++)
        ExpenseSplit(
          id: UniqueId.generate().value,
          expenseId: params.expenseId,
          memberId: params.inputs[i].memberId,
          value: baseAmount + (i < remainder ? 1 : 0),
          amountCents: baseAmount + (i < remainder ? 1 : 0),
        ),
    ]);
  }

  Either<Failure, List<ExpenseSplit>> _calculatePercentage(
      CalculateSplitsParams params) {
    final totalScaled = params.inputs.fold(0, (sum, i) => sum + i.value);
    // Total should be 10000 (= 100.00%)
    if (totalScaled != 10000) {
      return left(const ExpenseFailure.percentageDoesNotSumTo100());
    }

    final splits = <ExpenseSplit>[];
    var allocated = 0;

    for (var i = 0; i < params.inputs.length; i++) {
      final input = params.inputs[i];
      final isLast = i == params.inputs.length - 1;

      // Last member gets the remainder to avoid rounding loss
      final amountCents = isLast
          ? params.totalAmountCents - allocated
          : (params.totalAmountCents * input.value ~/ 10000);

      splits.add(ExpenseSplit(
        id: UniqueId.generate().value,
        expenseId: params.expenseId,
        memberId: input.memberId,
        value: input.value,
        amountCents: amountCents,
      ));
      allocated += amountCents;
    }

    return right(splits);
  }

  Either<Failure, List<ExpenseSplit>> _validateExact(
      CalculateSplitsParams params) {
    final total = params.inputs.fold(0, (sum, i) => sum + i.value);
    if (total != params.totalAmountCents) {
      return left(const ExpenseFailure.exactDoesNotSumToTotal());
    }

    return right([
      for (final input in params.inputs)
        ExpenseSplit(
          id: UniqueId.generate().value,
          expenseId: params.expenseId,
          memberId: input.memberId,
          value: input.value,
          amountCents: input.value,
        ),
    ]);
  }

  Either<Failure, List<ExpenseSplit>> _calculateShares(
      CalculateSplitsParams params) {
    if (params.inputs.any((i) => i.value <= 0)) {
      return left(const ExpenseFailure.invalidShares());
    }

    final totalShares = params.inputs.fold(0, (sum, i) => sum + i.value);
    final splits = <ExpenseSplit>[];
    var allocated = 0;

    for (var i = 0; i < params.inputs.length; i++) {
      final input = params.inputs[i];
      final isLast = i == params.inputs.length - 1;

      final amountCents = isLast
          ? params.totalAmountCents - allocated
          : (params.totalAmountCents * input.value ~/ totalShares);

      splits.add(ExpenseSplit(
        id: UniqueId.generate().value,
        expenseId: params.expenseId,
        memberId: input.memberId,
        value: input.value,
        amountCents: amountCents,
      ));
      allocated += amountCents;
    }

    return right(splits);
  }
}
