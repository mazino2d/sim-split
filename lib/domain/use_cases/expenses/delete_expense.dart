import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';
import 'package:simsplit/domain/use_cases/groups/group_guard.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class DeleteExpenseParams {
  const DeleteExpenseParams({required this.id});
  final String id;
}

class DeleteExpense implements AsyncUseCase<Unit, DeleteExpenseParams> {
  const DeleteExpense({
    required ExpenseRepository expenseRepository,
    required GroupRepository groupRepository,
  })  : _expenseRepository = expenseRepository,
        _groupRepository = groupRepository;

  final ExpenseRepository _expenseRepository;
  final GroupRepository _groupRepository;

  @override
  Future<Either<Failure, Unit>> call(DeleteExpenseParams params) async {
    final existing = await _expenseRepository.getExpense(params.id);
    if (existing case Left(value: final failure)) return left(failure);
    if (await ensureGroupWritable(
            _groupRepository, existing.toNullable()!.groupId)
        case Left(value: final failure)) {
      return left(failure);
    }
    return _expenseRepository.deleteExpense(params.id);
  }
}
