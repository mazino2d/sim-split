import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/invite_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Leaves a shared group, keeping its history (AC14).
class LeaveGroup implements AsyncUseCase<Unit, String> {
  const LeaveGroup({required InviteRepository inviteRepository})
      : _inviteRepository = inviteRepository;

  final InviteRepository _inviteRepository;

  @override
  Future<Either<Failure, Unit>> call(String params) =>
      _inviteRepository.leaveGroup(params);
}
