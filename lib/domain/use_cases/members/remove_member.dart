import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class RemoveMemberParams {
  const RemoveMemberParams({required this.memberId, required this.groupId});
  final String memberId;
  final String groupId;
}

/// Removes a member from a group.
///
/// Fails with:
/// - [MemberFailure.notFound] if the member does not exist,
/// - [MemberFailure.notInGroup] if the member belongs to another group,
/// - [MemberFailure.hasHistory] if the member is referenced by any expense
///   (including soft-deleted ones), split, or settlement.
class RemoveMember implements AsyncUseCase<Unit, RemoveMemberParams> {
  const RemoveMember({required MemberRepository memberRepository})
      : _memberRepository = memberRepository;

  final MemberRepository _memberRepository;

  @override
  Future<Either<Failure, Unit>> call(RemoveMemberParams params) async {
    final memberResult = await _memberRepository.getMember(params.memberId);
    switch (memberResult) {
      case Left(value: final failure):
        return left(failure);
      case Right(value: final member) when member.groupId != params.groupId:
        return left(const MemberFailure.notInGroup());
      case Right():
        break;
    }

    final referencedResult =
        await _memberRepository.isMemberReferenced(params.memberId);
    switch (referencedResult) {
      case Left(value: final failure):
        return left(failure);
      case Right(value: true):
        return left(const MemberFailure.hasHistory());
      case Right(value: false):
        return _memberRepository.removeMember(params.memberId);
    }
  }
}
