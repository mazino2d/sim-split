import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/sync_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// IDs of a group's records whose latest change has not reached the cloud
/// yet (AC16).
class WatchUnsyncedRecordIds implements StreamUseCase<Set<String>, String> {
  const WatchUnsyncedRecordIds({required SyncRepository syncRepository})
      : _syncRepository = syncRepository;

  final SyncRepository _syncRepository;

  @override
  Stream<Either<Failure, Set<String>>> call(String groupId) =>
      _syncRepository.watchUnsyncedRecordIds(groupId);
}
