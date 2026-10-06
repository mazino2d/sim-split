import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/invite_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// The link that invites friends to a group (AC9).
class GetInviteLink implements AsyncUseCase<Uri, String> {
  const GetInviteLink({required InviteRepository inviteRepository})
      : _inviteRepository = inviteRepository;

  final InviteRepository _inviteRepository;

  @override
  Future<Either<Failure, Uri>> call(String params) =>
      _inviteRepository.inviteLink(params);
}
