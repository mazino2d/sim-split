import 'package:fpdart/fpdart.dart';
import '../../entities/expense.dart';
import '../../failures/core_failure.dart';
import '../../repositories/expense_repository.dart';
import '../use_case.dart';

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
