import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/sync_failure.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';
import 'package:simsplit/domain/repositories/local_data_repository.dart';
import 'package:simsplit/domain/repositories/notification_repository.dart';
import 'package:simsplit/domain/repositories/sync_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Signs out and removes the account's data from this device (AC5).
///
/// Refuses while local changes are still waiting to be pushed, because
/// removing the device's data would lose them. This device is removed from
/// the account's push devices first, while the account can still write
/// (R-9 AC23); a failure there doesn't stop the sign-out.
class SignOut implements AsyncUseCase<Unit, NoParams> {
  const SignOut({
    required AuthRepository authRepository,
    required LocalDataRepository localDataRepository,
    required SyncRepository syncRepository,
    required NotificationRepository notificationRepository,
  })  : _authRepository = authRepository,
        _localDataRepository = localDataRepository,
        _syncRepository = syncRepository,
        _notificationRepository = notificationRepository;

  final AuthRepository _authRepository;
  final LocalDataRepository _localDataRepository;
  final SyncRepository _syncRepository;
  final NotificationRepository _notificationRepository;

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
    // Best effort: the repository logs a failure, and the sender drops a
    // token that no longer works (R-9 P3).
    await _notificationRepository.unregisterDevice();
    // The device is cleared before the session ends: once it has, another
    // account can sign in at once, and its pulled data must not be wiped by
    // this cleanup. Nothing is lost, since every change is in the cloud.
    await _syncRepository.stop();
    final cleared = await _localDataRepository.clearAll();
    if (cleared.isLeft()) return cleared;
    return _authRepository.signOut();
  }
}
