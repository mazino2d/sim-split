import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/use_cases/expenses/add_expense.dart';
import 'package:simsplit/domain/use_cases/expenses/calculate_splits.dart';
import 'package:simsplit/domain/use_cases/expenses/delete_expense.dart';
import 'package:simsplit/domain/use_cases/expenses/edit_expense.dart';

part 'expense_notifier.g.dart';

@riverpod
class ExpenseNotifier extends _$ExpenseNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> addExpense({
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
  }) async {
    state = const AsyncLoading();
    final useCase = ref.read(addExpenseProvider);
    final result = await useCase(AddExpenseParams(
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
    ));

    return result.fold(
      (failure) {
        state = AsyncError(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncData(null);
        return true;
      },
    );
  }

  Future<bool> editExpense({
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
  }) async {
    state = const AsyncLoading();
    final useCase = ref.read(editExpenseProvider);
    final result = await useCase(EditExpenseParams(
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
    ));

    return result.fold(
      (failure) {
        state = AsyncError(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncData(null);
        return true;
      },
    );
  }

  Future<bool> deleteExpense(String id) async {
    state = const AsyncLoading();
    final useCase = ref.read(deleteExpenseProvider);
    final result = await useCase(DeleteExpenseParams(id: id));

    return result.fold(
      (failure) {
        state = AsyncError(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncData(null);
        return true;
      },
    );
  }
}
