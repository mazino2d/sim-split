import 'package:fpdart/fpdart.dart';
import '../../entities/member.dart';
import '../../failures/core_failure.dart';
import '../../repositories/member_repository.dart';
import '../use_case.dart';

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
