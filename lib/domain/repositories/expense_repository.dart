import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

abstract interface class ExpenseRepository {
  /// Streams non-deleted expenses for a group, newest first.
  Stream<Either<Failure, List<Expense>>> watchExpensesByGroup(String groupId);
  Future<Either<Failure, Expense>> getExpense(String id);
  Future<Either<Failure, Expense>> addExpense(Expense expense);
  Future<Either<Failure, Expense>> updateExpense(Expense expense);

  /// Soft-deletes the expense (sets isDeleted = true).
  Future<Either<Failure, Unit>> deleteExpense(String id);
}
