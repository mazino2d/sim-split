import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/use_cases/expenses/list_expenses.dart';
import 'package:simsplit/core/di/injection.dart';

part 'expense_providers.g.dart';

/// Reactive stream of non-deleted expenses for a group, newest first.
@riverpod
Stream<List<Expense>> expenseList(Ref ref, String groupId) {
  final useCase = ref.watch(listExpensesProvider);
  return useCase(ListExpensesParams(groupId: groupId)).map(
    (either) => either.fold(
      (failure) => throw Exception(failure.toString()),
      (expenses) => expenses,
    ),
  );
}
