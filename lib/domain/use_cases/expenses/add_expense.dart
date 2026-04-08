import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/value_objects/unique_id.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/domain/use_cases/expenses/calculate_splits.dart';

class AddExpenseParams {
  const AddExpenseParams({
    required this.groupId,
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

  final String groupId;
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

class AddExpense implements AsyncUseCase<Expense, AddExpenseParams> {
  const AddExpense({
    required ExpenseRepository expenseRepository,
    required MemberRepository memberRepository,
    required CalculateSplits calculateSplits,
  })  : _expenseRepository = expenseRepository,
        _memberRepository = memberRepository,
        _calculateSplits = calculateSplits;

  final ExpenseRepository _expenseRepository;
  final MemberRepository _memberRepository;
  final CalculateSplits _calculateSplits;

  @override
  Future<Either<Failure, Expense>> call(AddExpenseParams params) async {
    if (params.amountCents <= 0) {
      return left(const ExpenseFailure.amountMustBePositive());
    }

    // Validate payer exists
    final payerResult =
        await _memberRepository.getMember(params.paidByMemberId);
    if (payerResult.isLeft()) {
      return left(const ExpenseFailure.memberNotFound());
    }

    final expenseId = UniqueId.generate().value;

    // Compute splits (pure domain logic)
    final splitsResult = _calculateSplits(
      CalculateSplitsParams(
        expenseId: expenseId,
        totalAmountCents: params.amountCents,
        splitType: params.splitType,
        inputs: params.splitInputs,
      ),
    );

    return splitsResult.fold(
      (failure) => left(failure),
      (splits) {
        final now = DateTime.now();
        final expense = Expense(
          id: expenseId,
          groupId: params.groupId,
          title: params.title.trim(),
          amountCents: params.amountCents,
          currencyCode: params.currencyCode,
          paidByMemberId: params.paidByMemberId,
          splitType: params.splitType,
          category: params.category,
          note: params.note?.trim(),
          expenseDate: params.expenseDate ?? now,
          createdAt: now,
          updatedAt: now,
          splits: splits,
        );
        return _expenseRepository.addExpense(expense);
      },
    );
  }
}
