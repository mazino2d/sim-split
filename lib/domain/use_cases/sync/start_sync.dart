import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/sync_repository.dart';
import 'package:simsplit/domain/repositories/user_profile_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Uploads local data on first sign-in, keeps pushing changes and pulls the
/// account's groups (AC7, AC15, AC16).
///
/// The rules require the account's profile (its privacy policy agreement,
/// R-4) for every group read and write, and sync can start as soon as
/// Firebase reports the sign-in, before SignInWithGoogle has stored it. So
/// the agreement is stored here first too; it is idempotent.
class StartSync implements AsyncUseCase<Unit, AuthUser> {
  const StartSync({
    required SyncRepository syncRepository,
    required UserProfileRepository userProfileRepository,
    required String policyVersion,
  })  : _syncRepository = syncRepository,
        _userProfileRepository = userProfileRepository,
        _policyVersion = policyVersion;

  final SyncRepository _syncRepository;
  final UserProfileRepository _userProfileRepository;
  final String _policyVersion;

  @override
  Future<Either<Failure, Unit>> call(AuthUser user) async {
    final agreed =
        await _userProfileRepository.recordAgreement(user, _policyVersion);
    if (agreed.isLeft()) return agreed;
    return _syncRepository.start(user);
  }
}
