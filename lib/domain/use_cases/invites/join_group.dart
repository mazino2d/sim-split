import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';
import 'package:simsplit/domain/repositories/invite_repository.dart';
import 'package:simsplit/domain/repositories/user_profile_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Joins the group an invite link points to (AC10).
///
/// The rules require the account's profile (its privacy policy agreement,
/// R-4) to read an invite. A friend who signs in for the first time from an
/// invite link reaches the join screen as soon as Firebase reports the
/// sign-in, before SignInWithGoogle has stored the agreement, so the read
/// would be denied and look like an invalid link (#107). The agreement is
/// stored here first too; it is idempotent.
class JoinGroup implements AsyncUseCase<String, String> {
  const JoinGroup({
    required InviteRepository inviteRepository,
    required AuthRepository authRepository,
    required UserProfileRepository userProfileRepository,
    required String policyVersion,
  })  : _inviteRepository = inviteRepository,
        _authRepository = authRepository,
        _userProfileRepository = userProfileRepository,
        _policyVersion = policyVersion;

  final InviteRepository _inviteRepository;
  final AuthRepository _authRepository;
  final UserProfileRepository _userProfileRepository;
  final String _policyVersion;

  @override
  Future<Either<Failure, String>> call(String params) async {
    final current = await _authRepository.watchCurrentUser().first;
    if (current case Left(value: final failure)) return left(failure);
    final user = current.toNullable();
    if (user == null) {
      return left(const Failure.unexpected('Joining a group needs sign-in'));
    }
    final agreed =
        await _userProfileRepository.recordAgreement(user, _policyVersion);
    if (agreed case Left(value: final failure)) return left(failure);
    return _inviteRepository.joinGroup(params);
  }
}
