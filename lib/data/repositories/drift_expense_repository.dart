import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/data/daos/expense_dao.dart';
import 'package:simsplit/data/daos/expense_split_dao.dart';
import 'package:simsplit/data/mappers/expense_mapper.dart';
import 'package:simsplit/data/utils/stream_failure_transformer.dart';

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
    // A single JOIN query watches both the expenses and the splits table, so
    // every emission carries up-to-date splits for each expense.
    return _expenseDao
        .watchExpensesWithSplitsByGroup(groupId)
        .map((rows) => right<Failure, List<Expense>>([
              for (final (row, splits) in rows) _mapper.toEntity(row, splits),
            ]))
        .mapErrorsToDbFailure();
  }

  @override
  Future<Either<Failure, Expense>> getExpense(String id) async {
    try {
      final row = await _expenseDao.getExpenseById(id);
      // Soft-deleted expenses are treated as non-existent.
      if (row == null || row.isDeleted) {
        return left(const ExpenseFailure.notFound());
      }
      final splits = await _expenseSplitDao.getSplitsForExpense(id);
      return right(_mapper.toEntity(row, splits));
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Expense>> addExpense(Expense expense) async {
    try {
      // Expense row and splits are written atomically.
      await _expenseDao.attachedDatabase.transaction(() async {
        await _expenseDao.insertExpense(_mapper.toCompanion(expense));
        await _expenseSplitDao
            .insertSplits(_mapper.splitCompanions(expense.splits));
      });
      return right(expense);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Expense>> updateExpense(Expense expense) async {
    try {
      // Replace expense row and re-insert splits atomically.
      final replaced = await _expenseDao.attachedDatabase.transaction(() async {
        final ok =
            await _expenseDao.updateExpenseById(_mapper.toCompanion(expense));
        if (!ok) return false;
        await _expenseSplitDao.deleteSplitsForExpense(expense.id);
        await _expenseSplitDao
            .insertSplits(_mapper.splitCompanions(expense.splits));
        return true;
      });
      if (!replaced) return left(const ExpenseFailure.notFound());
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
