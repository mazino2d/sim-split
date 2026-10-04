import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';
import 'package:simsplit/domain/repositories/local_data_repository.dart';
import 'package:simsplit/domain/repositories/sync_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Deletes the account: first its cloud data (leave shared groups, delete
/// groups where it is the only member), then the account itself, then the
/// data on this device (AC6). Cloud data goes first because it can only be
/// changed while the account still exists.
class DeleteAccount implements AsyncUseCase<Unit, NoParams> {
  const DeleteAccount({
    required AuthRepository authRepository,
    required LocalDataRepository localDataRepository,
    required SyncRepository syncRepository,
  })  : _authRepository = authRepository,
        _localDataRepository = localDataRepository,
        _syncRepository = syncRepository;

  final AuthRepository _authRepository;
  final LocalDataRepository _localDataRepository;
  final SyncRepository _syncRepository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    final cloud = await _syncRepository.deleteCloudData();
    if (cloud.isLeft()) return cloud;
    final deleted = await _authRepository.deleteAccount();
    if (deleted.isLeft()) return deleted;
    return _localDataRepository.clearAll();
  }
}
