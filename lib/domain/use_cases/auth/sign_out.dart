import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/sync_failure.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';
import 'package:simsplit/domain/repositories/local_data_repository.dart';
import 'package:simsplit/domain/repositories/sync_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Signs out and removes the account's data from this device (AC5).
///
/// Refuses while local changes are still waiting to be pushed, because
/// removing the device's data would lose them.
class SignOut implements AsyncUseCase<Unit, NoParams> {
  const SignOut({
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
    final pending = await _syncRepository.pendingChangeCount();
    switch (pending) {
      case Left(value: final failure):
        return left(failure);
      case Right(value: final count) when count > 0:
        return left(SyncFailure.unsyncedChanges(count));
      case Right():
        break;
    }
    // The device is cleared before the session ends: once it has, another
    // account can sign in at once, and its pulled data must not be wiped by
    // this cleanup. Nothing is lost, since every change is in the cloud.
    await _syncRepository.stop();
    final cleared = await _localDataRepository.clearAll();
    if (cleared.isLeft()) return cleared;
    return _authRepository.signOut();
  }
}
