import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class ListExpensesParams {
  const ListExpensesParams({required this.groupId});
  final String groupId;
}

class ListExpenses implements StreamUseCase<List<Expense>, ListExpensesParams> {
  const ListExpenses({required ExpenseRepository expenseRepository})
      : _expenseRepository = expenseRepository;

  final ExpenseRepository _expenseRepository;

  @override
  Stream<Either<Failure, List<Expense>>> call(ListExpensesParams params) =>
      _expenseRepository.watchExpensesByGroup(params.groupId);
}
