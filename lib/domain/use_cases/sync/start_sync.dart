import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/sync_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Uploads local data on first sign-in and keeps pushing changes (AC7,
/// AC16).
class StartSync implements AsyncUseCase<Unit, AuthUser> {
  const StartSync({required SyncRepository syncRepository})
      : _syncRepository = syncRepository;

  final SyncRepository _syncRepository;

  @override
  Future<Either<Failure, Unit>> call(AuthUser user) =>
      _syncRepository.start(user);
}
