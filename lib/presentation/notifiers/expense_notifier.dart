import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/expenses/add_expense.dart';
import 'package:simsplit/domain/use_cases/expenses/calculate_splits.dart';
import 'package:simsplit/domain/use_cases/expenses/delete_expense.dart';
import 'package:simsplit/domain/use_cases/expenses/edit_expense.dart';

part 'expense_notifier.g.dart';

/// Expense mutations. Each method returns the use case result directly so
/// callers never depend on reading [state] after an `await` (the notifier is
/// auto-disposed and may have been recreated by then).
@riverpod
class ExpenseNotifier extends _$ExpenseNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<Either<Failure, T>> _run<T>(
    Future<Either<Failure, T>> Function() action,
  ) async {
    state = const AsyncLoading();
    final result = await action();
    if (ref.mounted) {
      state = result.fold(
        (failure) => AsyncError(failure, StackTrace.current),
        (_) => const AsyncData(null),
      );
    }
    return result;
  }

  Future<Either<Failure, Expense>> addExpense({
    required String groupId,
    required String title,
    required int amountCents,
    required String currencyCode,
    required String paidByMemberId,
    required SplitType splitType,
    required List<RawSplitInput> splitInputs,
    ExpenseCategory category = ExpenseCategory.other,
    String? note,
    DateTime? expenseDate,
  }) {
    final useCase = ref.read(addExpenseProvider);
    return _run(() => useCase(AddExpenseParams(
          groupId: groupId,
          title: title,
          amountCents: amountCents,
          currencyCode: currencyCode,
          paidByMemberId: paidByMemberId,
          splitType: splitType,
          splitInputs: splitInputs,
          category: category,
          note: note,
          expenseDate: expenseDate,
        )));
  }

  Future<Either<Failure, Expense>> editExpense({
    required String id,
    required String title,
    required int amountCents,
    required String currencyCode,
    required String paidByMemberId,
    required SplitType splitType,
    required List<RawSplitInput> splitInputs,
    ExpenseCategory category = ExpenseCategory.other,
    String? note,
    DateTime? expenseDate,
  }) {
    final useCase = ref.read(editExpenseProvider);
    return _run(() => useCase(EditExpenseParams(
          id: id,
          title: title,
          amountCents: amountCents,
          currencyCode: currencyCode,
          paidByMemberId: paidByMemberId,
          splitType: splitType,
          splitInputs: splitInputs,
          category: category,
          note: note,
          expenseDate: expenseDate,
        )));
  }

  Future<Either<Failure, Unit>> deleteExpense(String id) {
    final useCase = ref.read(deleteExpenseProvider);
    return _run(() => useCase(DeleteExpenseParams(id: id)));
  }
}
