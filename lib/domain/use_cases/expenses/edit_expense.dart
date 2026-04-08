import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/domain/use_cases/expenses/calculate_splits.dart';

class EditExpenseParams {
  const EditExpenseParams({
    required this.id,
    required this.title,
    required this.amountCents,
    required this.currencyCode,
    required this.paidByMemberId,
    required this.splitType,
    required this.splitInputs,
    this.category = ExpenseCategory.other,
    this.note,
    this.expenseDate,
  });

  final String id;
  final String title;
  final int amountCents;
  final String currencyCode;
  final String paidByMemberId;
  final SplitType splitType;
  final List<RawSplitInput> splitInputs;
  final ExpenseCategory category;
  final String? note;
  final DateTime? expenseDate;
}

class EditExpense implements AsyncUseCase<Expense, EditExpenseParams> {
  const EditExpense({
    required ExpenseRepository expenseRepository,
    required CalculateSplits calculateSplits,
  })  : _expenseRepository = expenseRepository,
        _calculateSplits = calculateSplits;

  final ExpenseRepository _expenseRepository;
  final CalculateSplits _calculateSplits;

  @override
  Future<Either<Failure, Expense>> call(EditExpenseParams params) async {
    if (params.amountCents <= 0) {
      return left(const ExpenseFailure.amountMustBePositive());
    }

    final existingResult = await _expenseRepository.getExpense(params.id);
    return existingResult.fold<Future<Either<Failure, Expense>>>(
      (failure) async => left(failure),
      (existing) async {
        final splitsResult = _calculateSplits(
          CalculateSplitsParams(
            expenseId: params.id,
            totalAmountCents: params.amountCents,
            splitType: params.splitType,
            inputs: params.splitInputs,
          ),
        );

        return splitsResult.fold(
          (failure) => Future.value(left(failure)),
          (splits) {
            final updated = existing.copyWith(
              title: params.title.trim(),
              amountCents: params.amountCents,
              currencyCode: params.currencyCode,
              paidByMemberId: params.paidByMemberId,
              splitType: params.splitType,
              category: params.category,
              note: params.note?.trim(),
              expenseDate: params.expenseDate ?? existing.expenseDate,
              updatedAt: DateTime.now(),
              splits: splits,
            );
            return _expenseRepository.updateExpense(updated);
          },
        );
      },
    );
  }
}
