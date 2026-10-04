import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';
import 'package:simsplit/domain/repositories/local_data_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Deletes the account and removes its data from this device (AC6).
class DeleteAccount implements AsyncUseCase<Unit, NoParams> {
  const DeleteAccount({
    required AuthRepository authRepository,
    required LocalDataRepository localDataRepository,
  })  : _authRepository = authRepository,
        _localDataRepository = localDataRepository;

  final AuthRepository _authRepository;
  final LocalDataRepository _localDataRepository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    final deleted = await _authRepository.deleteAccount();
    if (deleted.isLeft()) return deleted;
    return _localDataRepository.clearAll();
  }
}
