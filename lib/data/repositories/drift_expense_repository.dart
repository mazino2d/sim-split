import 'package:drift/drift.dart' show Value;
import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/data/daos/expense_dao.dart';
import 'package:simsplit/data/daos/expense_split_dao.dart';
import 'package:simsplit/data/mappers/expense_mapper.dart';
import 'package:simsplit/data/sync/sync_codec.dart';
import 'package:simsplit/data/sync/sync_recorder.dart';
import 'package:simsplit/data/utils/stream_failure_transformer.dart';

class DriftExpenseRepository implements ExpenseRepository {
  const DriftExpenseRepository({
    required ExpenseDao expenseDao,
    required ExpenseSplitDao expenseSplitDao,
    required ExpenseMapper mapper,
    required SyncRecorder recorder,
    SyncCodec codec = const SyncCodec(),
  })  : _expenseDao = expenseDao,
        _expenseSplitDao = expenseSplitDao,
        _mapper = mapper,
        _recorder = recorder,
        _codec = codec;

  final ExpenseDao _expenseDao;
  final ExpenseSplitDao _expenseSplitDao;
  final ExpenseMapper _mapper;
  final SyncRecorder _recorder;
  final SyncCodec _codec;

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

  /// The stored expense with its splits, as a sync snapshot.
  Future<Map<String, Object?>> _snapshot(String id) async => _codec.expense(
        (await _expenseDao.getExpenseById(id))!,
        await _expenseSplitDao.getSplitsForExpense(id),
      );

  @override
  Future<Either<Failure, Expense>> addExpense(Expense expense) async {
    try {
      // Expense row, splits and the sync record are written atomically.
      await _expenseDao.transaction(() async {
        final uid = _recorder.uid;
        await _expenseDao.insertExpense(_mapper.toCompanion(expense).copyWith(
              createdBy: Value(uid),
              updatedBy: Value(uid),
            ));
        await _expenseSplitDao
            .insertSplits(_mapper.splitCompanions(expense.splits));
        await _recorder.record(
          groupId: expense.groupId,
          entity: SyncEntity.expense,
          entityId: expense.id,
          action: SyncAction.create,
          after: await _snapshot(expense.id),
        );
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
      final replaced = await _expenseDao.transaction(() async {
        final row = await _expenseDao.getExpenseById(expense.id);
        if (row == null) return false;
        final before = await _snapshot(expense.id);
        await _expenseDao.updateExpenseById(_mapper
            .toCompanion(expense)
            .copyWith(updatedBy: Value(_recorder.uid ?? row.updatedBy)));
        await _expenseSplitDao.deleteSplitsForExpense(expense.id);
        await _expenseSplitDao
            .insertSplits(_mapper.splitCompanions(expense.splits));
        await _recorder.record(
          groupId: expense.groupId,
          entity: SyncEntity.expense,
          entityId: expense.id,
          action: SyncAction.update,
          before: before,
          after: await _snapshot(expense.id),
        );
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
      await _expenseDao.transaction(() async {
        final row = await _expenseDao.getExpenseById(id);
        if (row == null || row.isDeleted) return;
        final before = await _snapshot(id);
        await _expenseDao.softDeleteExpense(id,
            updatedBy: _recorder.uid ?? row.updatedBy);
        await _recorder.record(
          groupId: row.groupId,
          entity: SyncEntity.expense,
          entityId: id,
          action: SyncAction.delete,
          before: before,
          after: await _snapshot(id),
        );
      });
      return right(unit);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }
}
