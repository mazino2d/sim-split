import 'package:fpdart/fpdart.dart';
import '../entities/member.dart';
import '../failures/core_failure.dart';

abstract interface class MemberRepository {
  Stream<Either<Failure, List<Member>>> watchMembersByGroup(String groupId);
  Future<Either<Failure, Member>> getMember(String id);
  Future<Either<Failure, Member>> addMember(Member member);
  Future<Either<Failure, Member>> updateMember(Member member);
  Future<Either<Failure, Unit>> removeMember(String id);
}
