import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/invite_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Joins the group an invite link points to (AC10).
class JoinGroup implements AsyncUseCase<String, String> {
  const JoinGroup({required InviteRepository inviteRepository})
      : _inviteRepository = inviteRepository;

  final InviteRepository _inviteRepository;

  @override
  Future<Either<Failure, String>> call(String params) =>
      _inviteRepository.joinGroup(params);
}
