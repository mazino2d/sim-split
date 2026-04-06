import 'package:fpdart/fpdart.dart';
import '../../failures/core_failure.dart';
import '../../repositories/expense_repository.dart';
import '../use_case.dart';

class DeleteExpenseParams {
  const DeleteExpenseParams({required this.id});
  final String id;
}

class DeleteExpense implements AsyncUseCase<Unit, DeleteExpenseParams> {
  const DeleteExpense({required ExpenseRepository expenseRepository})
      : _expenseRepository = expenseRepository;

  final ExpenseRepository _expenseRepository;

  @override
  Future<Either<Failure, Unit>> call(DeleteExpenseParams params) =>
      _expenseRepository.deleteExpense(params.id);
}
