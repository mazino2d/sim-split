import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class SignInWithGoogle implements AsyncUseCase<AuthUser, NoParams> {
  const SignInWithGoogle({required AuthRepository authRepository})
      : _authRepository = authRepository;

  final AuthRepository _authRepository;

  @override
  Future<Either<Failure, AuthUser>> call(NoParams params) =>
      _authRepository.signInWithGoogle();
}
