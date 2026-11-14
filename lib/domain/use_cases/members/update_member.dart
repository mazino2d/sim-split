import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';
import 'package:simsplit/domain/use_cases/groups/group_guard.dart';
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
  const UpdateMember({
    required MemberRepository memberRepository,
    required GroupRepository groupRepository,
  })  : _memberRepository = memberRepository,
        _groupRepository = groupRepository;

  final MemberRepository _memberRepository;
  final GroupRepository _groupRepository;

  @override
  Future<Either<Failure, Member>> call(UpdateMemberParams params) async {
    if (params.name.trim().isEmpty) {
      return left(const MemberFailure.nameEmpty());
    }
    if (await ensureGroupWritable(_groupRepository, params.groupId)
        case Left(value: final failure)) {
      return left(failure);
    }
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
