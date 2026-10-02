import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

abstract interface class MemberRepository {
  Stream<Either<Failure, List<Member>>> watchMembersByGroup(String groupId);
  Future<Either<Failure, Member>> getMember(String id);
  Future<Either<Failure, Member>> addMember(Member member);
  Future<Either<Failure, Member>> updateMember(Member member);
  Future<Either<Failure, Unit>> removeMember(String id);

  /// Whether the member is referenced by any expense (as payer, including
  /// soft-deleted expenses), any expense split, or any settlement.
  Future<Either<Failure, bool>> isMemberReferenced(String memberId);
}
