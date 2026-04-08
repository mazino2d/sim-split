import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

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
