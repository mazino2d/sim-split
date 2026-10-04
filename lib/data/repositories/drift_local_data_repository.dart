import 'package:fpdart/fpdart.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/local_data_repository.dart';

class DriftLocalDataRepository implements LocalDataRepository {
  const DriftLocalDataRepository({required AppDatabase database})
      : _db = database;

  final AppDatabase _db;

  @override
  Future<Either<Failure, Unit>> clearAll() async {
    try {
      // Children before parents, so foreign keys never point at a gap.
      await _db.transaction(() async {
        await _db.delete(_db.outboxEntries).go();
        await _db.delete(_db.activities).go();
        await _db.delete(_db.syncStates).go();
        await _db.delete(_db.expenseSplits).go();
        await _db.delete(_db.settlements).go();
        await _db.delete(_db.expenses).go();
        await _db.delete(_db.members).go();
        await _db.delete(_db.groups).go();
      });
      return right(unit);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }
}
