import 'package:fpdart/fpdart.dart';
import '../../entities/member.dart';
import '../../failures/core_failure.dart';
import '../../repositories/member_repository.dart';
import '../../value_objects/unique_id.dart';
import '../use_case.dart';

class AddMemberParams {
  const AddMemberParams({
    required this.groupId,
    required this.name,
    this.avatarColorValue = 0xFF6200EE,
    this.isMe = false,
  });

  final String groupId;
  final String name;
  final int avatarColorValue;
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
      isMe: params.isMe,
      createdAt: DateTime.now(),
    );
    return _memberRepository.addMember(member);
  }
}
