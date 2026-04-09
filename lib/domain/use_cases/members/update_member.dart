import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class UpdateMemberParams {
  const UpdateMemberParams({
    required this.id,
    required this.groupId,
    required this.name,
    required this.avatarColorValue,
    this.emoji,
    required this.isMe,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String name;
  final int avatarColorValue;
  final String? emoji;
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
      emoji: params.emoji,
      isMe: params.isMe,
      createdAt: params.createdAt,
    );
    return _memberRepository.updateMember(member);
  }
}
