import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';
import 'package:simsplit/domain/repositories/local_data_repository.dart';
import 'package:simsplit/domain/repositories/notification_repository.dart';
import 'package:simsplit/domain/repositories/sync_repository.dart';
import 'package:simsplit/domain/repositories/user_profile_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Deletes the account: first its cloud data (leave shared groups, delete
/// groups where it is the only member, delete its push devices (R-9 AC23),
/// delete its profile), then the account
/// itself, then the data on this device (AC6). Cloud data goes first because
/// it can only be changed while the account still exists. The warehouse
/// drops the profile on its next daily load (R-4 AC11).
class DeleteAccount implements AsyncUseCase<Unit, NoParams> {
  const DeleteAccount({
    required AuthRepository authRepository,
    required LocalDataRepository localDataRepository,
    required SyncRepository syncRepository,
    required UserProfileRepository userProfileRepository,
    required NotificationRepository notificationRepository,
  })  : _authRepository = authRepository,
        _localDataRepository = localDataRepository,
        _syncRepository = syncRepository,
        _userProfileRepository = userProfileRepository,
        _notificationRepository = notificationRepository;

  final AuthRepository _authRepository;
  final LocalDataRepository _localDataRepository;
  final SyncRepository _syncRepository;
  final UserProfileRepository _userProfileRepository;
  final NotificationRepository _notificationRepository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    final cloud = await _syncRepository.deleteCloudData();
    if (cloud.isLeft()) return cloud;
    // Firestore keeps a document's subcollections when it is deleted, so the
    // devices go before the profile.
    final devices = await _notificationRepository.deleteAllDevices();
    if (devices.isLeft()) return devices;
    final profile = await _userProfileRepository.deleteProfile();
    if (profile.isLeft()) return profile;
    final deleted = await _authRepository.deleteAccount();
    if (deleted.isLeft()) return deleted;
    return _localDataRepository.clearAll();
  }
}
