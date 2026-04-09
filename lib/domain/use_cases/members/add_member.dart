import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/value_objects/unique_id.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class AddMemberParams {
  const AddMemberParams({
    required this.groupId,
    required this.name,
    this.avatarColorValue = 0xFF1976D2,
    this.emoji,
    this.isMe = false,
  });

  final String groupId;
  final String name;
  final int avatarColorValue;
  final String? emoji;
  final bool isMe;
}

class AddMember implements AsyncUseCase<Member, AddMemberParams> {
  const AddMember({required MemberRepository memberRepository})
      : _memberRepository = memberRepository;

  final MemberRepository _memberRepository;

  @override
  Future<Either<Failure, Member>> call(AddMemberParams params) {
    final member = Member(
      id: UniqueId.generate().value,
      groupId: params.groupId,
      name: params.name.trim(),
      avatarColorValue: params.avatarColorValue,
      emoji: params.emoji,
      isMe: params.isMe,
      createdAt: DateTime.now(),
    );
    return _memberRepository.addMember(member);
  }
}
