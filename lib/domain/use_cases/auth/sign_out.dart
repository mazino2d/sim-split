import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';
import 'package:simsplit/domain/repositories/local_data_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Signs out and removes the account's data from this device (AC5).
class SignOut implements AsyncUseCase<Unit, NoParams> {
  const SignOut({
    required AuthRepository authRepository,
    required LocalDataRepository localDataRepository,
  })  : _authRepository = authRepository,
        _localDataRepository = localDataRepository;

  final AuthRepository _authRepository;
  final LocalDataRepository _localDataRepository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    final signedOut = await _authRepository.signOut();
    if (signedOut.isLeft()) return signedOut;
    return _localDataRepository.clearAll();
  }
}
