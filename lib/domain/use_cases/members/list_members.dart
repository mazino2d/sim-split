import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class ListMembersParams {
  const ListMembersParams({required this.groupId});
  final String groupId;
}

class ListMembers implements StreamUseCase<List<Member>, ListMembersParams> {
  const ListMembers({required MemberRepository memberRepository})
      : _memberRepository = memberRepository;

  final MemberRepository _memberRepository;

  @override
  Stream<Either<Failure, List<Member>>> call(ListMembersParams params) =>
      _memberRepository.watchMembersByGroup(params.groupId);
}
