import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/sync_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class StopSync implements AsyncUseCase<Unit, NoParams> {
  const StopSync({required SyncRepository syncRepository})
      : _syncRepository = syncRepository;

  final SyncRepository _syncRepository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) => _syncRepository.stop();
}
