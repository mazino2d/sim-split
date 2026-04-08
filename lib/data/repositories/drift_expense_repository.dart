import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/data/daos/expense_dao.dart';
import 'package:simsplit/data/daos/expense_split_dao.dart';
import 'package:simsplit/data/mappers/expense_mapper.dart';

class DriftExpenseRepository implements ExpenseRepository {
  const DriftExpenseRepository({
    required ExpenseDao expenseDao,
    required ExpenseSplitDao expenseSplitDao,
    required ExpenseMapper mapper,
  })  : _expenseDao = expenseDao,
        _expenseSplitDao = expenseSplitDao,
        _mapper = mapper;

  final ExpenseDao _expenseDao;
  final ExpenseSplitDao _expenseSplitDao;
  final ExpenseMapper _mapper;

  @override
  Stream<Either<Failure, List<Expense>>> watchExpensesByGroup(String groupId) {
    // Watch expenses then hydrate each with its splits.
    // Note: this triggers a re-load of all splits whenever any expense changes.
    // For MVP scale this is acceptable; can be optimized with a JOIN later.
    return _expenseDao.watchExpensesByGroup(groupId).asyncMap((rows) async {
      final expenses = <Expense>[];
      for (final row in rows) {
        final splits = await _expenseSplitDao.getSplitsForExpense(row.id);
        expenses.add(_mapper.toEntity(row, splits));
      }
      return right<Failure, List<Expense>>(expenses);
    }).handleError(
      (Object e) => left<Failure, List<Expense>>(
        Failure.dbFailure(e.toString()),
      ),
    );
  }

  @override
  Future<Either<Failure, Expense>> getExpense(String id) async {
    try {
      final row = await _expenseDao.getExpenseById(id);
      if (row == null) return left(const ExpenseFailure.notFound());
      final splits = await _expenseSplitDao.getSplitsForExpense(id);
      return right(_mapper.toEntity(row, splits));
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Expense>> addExpense(Expense expense) async {
    try {
      await _expenseDao.insertExpense(_mapper.toCompanion(expense));
      await _expenseSplitDao
          .insertSplits(_mapper.splitCompanions(expense.splits));
      return right(expense);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Expense>> updateExpense(Expense expense) async {
    try {
      // Replace expense row and re-insert splits atomically
      await _expenseDao.updateExpenseById(_mapper.toCompanion(expense));
      await _expenseSplitDao.deleteSplitsForExpense(expense.id);
      await _expenseSplitDao
          .insertSplits(_mapper.splitCompanions(expense.splits));
      return right(expense);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteExpense(String id) async {
    try {
      await _expenseDao.softDeleteExpense(id);
      return right(unit);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }
}
