import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';
import 'package:simsplit/domain/repositories/user_profile_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Signs in with Google. Signing in is agreeing to the privacy policy
/// (R-4 AC6, AC7): the agreement is stored with the account, and a sign-in
/// whose agreement cannot be stored is undone, like any failed sign-in.
class SignInWithGoogle implements AsyncUseCase<AuthUser, NoParams> {
  const SignInWithGoogle({
    required AuthRepository authRepository,
    required UserProfileRepository userProfileRepository,
    required String policyVersion,
  })  : _authRepository = authRepository,
        _userProfileRepository = userProfileRepository,
        _policyVersion = policyVersion;

  final AuthRepository _authRepository;
  final UserProfileRepository _userProfileRepository;
  final String _policyVersion;

  @override
  Future<Either<Failure, AuthUser>> call(NoParams params) async {
    final signedIn = await _authRepository.signInWithGoogle();
    final user = signedIn.toNullable();
    if (user == null) return signedIn;
    final agreed =
        await _userProfileRepository.recordAgreement(user, _policyVersion);
    if (agreed case Left(value: final failure)) {
      await _authRepository.signOut();
      return left(failure);
    }
    return right(user);
  }
}
