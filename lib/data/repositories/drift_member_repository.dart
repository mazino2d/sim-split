import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/settlement_failure.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/data/daos/member_dao.dart';
import 'package:simsplit/data/mappers/member_mapper.dart';

class DriftMemberRepository implements MemberRepository {
  const DriftMemberRepository({
    required MemberDao memberDao,
    required MemberMapper mapper,
  })  : _memberDao = memberDao,
        _mapper = mapper;

  final MemberDao _memberDao;
  final MemberMapper _mapper;

  @override
  Stream<Either<Failure, List<Member>>> watchMembersByGroup(String groupId) {
    return _memberDao
        .watchMembersByGroup(groupId)
        .map((rows) => right<Failure, List<Member>>(
              rows.map(_mapper.toEntity).toList(),
            ))
        .handleError(
          (Object e) => left<Failure, List<Member>>(
            Failure.dbFailure(e.toString()),
          ),
        );
  }

  @override
  Future<Either<Failure, Member>> getMember(String id) async {
    try {
      final row = await _memberDao.getMemberById(id);
      if (row == null) return left(const SettlementFailure.notFound());
      return right(_mapper.toEntity(row));
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Member>> addMember(Member member) async {
    try {
      await _memberDao.attachedDatabase.transaction(() async {
        if (member.isMe) {
          await _memberDao.clearIsMeForGroup(member.groupId);
        }
        await _memberDao.insertMember(_mapper.toCompanion(member));
      });
      return right(member);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Member>> updateMember(Member member) async {
    try {
      await _memberDao.attachedDatabase.transaction(() async {
        if (member.isMe) {
          await _memberDao.clearIsMeForGroup(member.groupId);
        }
        await _memberDao.updateMemberById(_mapper.toCompanion(member));
      });
      return right(member);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> removeMember(String id) async {
    try {
      await _memberDao.deleteMemberById(id);
      return right(unit);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }
}
