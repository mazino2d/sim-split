import 'package:fpdart/fpdart.dart';
import '../../entities/member.dart';
import '../../failures/core_failure.dart';
import '../../repositories/member_repository.dart';
import '../use_case.dart';

class UpdateMemberParams {
  const UpdateMemberParams({
    required this.id,
    required this.groupId,
    required this.name,
    required this.avatarColorValue,
    required this.isMe,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String name;
  final int avatarColorValue;
  final bool isMe;
  final DateTime createdAt;
}

class UpdateMember implements AsyncUseCase<Member, UpdateMemberParams> {
  const UpdateMember({required MemberRepository memberRepository})
      : _memberRepository = memberRepository;

  final MemberRepository _memberRepository;

  @override
  Future<Either<Failure, Member>> call(UpdateMemberParams params) {
    final member = Member(
      id: params.id,
      groupId: params.groupId,
      name: params.name.trim(),
      avatarColorValue: params.avatarColorValue,
      isMe: params.isMe,
      createdAt: params.createdAt,
    );
    return _memberRepository.updateMember(member);
  }
}
