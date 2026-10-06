import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/invite_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Replaces a group's invite link; old links stop working (AC13).
class ResetInviteLink implements AsyncUseCase<Uri, String> {
  const ResetInviteLink({required InviteRepository inviteRepository})
      : _inviteRepository = inviteRepository;

  final InviteRepository _inviteRepository;

  @override
  Future<Either<Failure, Uri>> call(String params) =>
      _inviteRepository.resetInviteLink(params);
}
