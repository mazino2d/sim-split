import 'package:drift/drift.dart' show Value;
import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/data/daos/member_dao.dart';
import 'package:simsplit/data/database/app_database.dart' as db;
import 'package:simsplit/data/mappers/member_mapper.dart';
import 'package:simsplit/data/sync/sync_codec.dart';
import 'package:simsplit/data/sync/sync_recorder.dart';
import 'package:simsplit/data/utils/stream_failure_transformer.dart';

/// Members, where "me" is also the signed-in account's claim: marking a
/// member as me links it to the account (`linkedUid`, AC7), and only one
/// member per group can be me.
class DriftMemberRepository implements MemberRepository {
  const DriftMemberRepository({
    required MemberDao memberDao,
    required MemberMapper mapper,
    required SyncRecorder recorder,
    SyncCodec codec = const SyncCodec(),
  })  : _memberDao = memberDao,
        _mapper = mapper,
        _recorder = recorder,
        _codec = codec;

  final MemberDao _memberDao;
  final MemberMapper _mapper;
  final SyncRecorder _recorder;
  final SyncCodec _codec;

  @override
  Stream<Either<Failure, List<Member>>> watchMembersByGroup(String groupId) {
    return _memberDao
        .watchMembersByGroup(groupId)
        .map((rows) => right<Failure, List<Member>>(
              rows.map(_mapper.toEntity).toList(),
            ))
        .mapErrorsToDbFailure();
  }

  @override
  Future<Either<Failure, Member>> getMember(String id) async {
    try {
      final row = await _memberDao.getMemberById(id);
      if (row == null || row.deleted) {
        return left(const MemberFailure.notFound());
      }
      return right(_mapper.toEntity(row));
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Member>> addMember(Member member) async {
    try {
      await _memberDao.transaction(() async {
        final uid = _recorder.uid;
        if (member.isMe) await _releaseMe(member.groupId, exceptId: member.id);
        await _memberDao.insertMember(_mapper.toCompanion(member).copyWith(
              linkedUid: Value(member.isMe ? uid : null),
              createdBy: Value(uid),
              updatedBy: Value(uid),
            ));
        await _recorder.record(
          groupId: member.groupId,
          entity: SyncEntity.member,
          entityId: member.id,
          action: SyncAction.create,
          after: _codec.member((await _memberDao.getMemberById(member.id))!),
        );
      });
      return right(member);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Member>> updateMember(Member member) async {
    try {
      final updated = await _memberDao.transaction(() async {
        final before = await _memberDao.getMemberById(member.id);
        if (before == null || before.deleted) return false;
        final uid = _recorder.uid;
        if (member.isMe) await _releaseMe(member.groupId, exceptId: member.id);
        await _memberDao.updateMemberById(_mapper.toCompanion(member).copyWith(
              linkedUid: Value(_linkedUid(before, isMe: member.isMe)),
              updatedBy: Value(uid ?? before.updatedBy),
            ));
        await _recorder.record(
          groupId: member.groupId,
          entity: SyncEntity.member,
          entityId: member.id,
          action: SyncAction.update,
          before: _codec.member(before),
          after: _codec.member((await _memberDao.getMemberById(member.id))!),
        );
        return true;
      });
      if (!updated) return left(const MemberFailure.notFound());
      return right(member);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> removeMember(String id) async {
    try {
      final removed = await _memberDao.transaction(() async {
        final before = await _memberDao.getMemberById(id);
        if (before == null || before.deleted) return false;
        await _memberDao.softDeleteMember(id,
            updatedBy: _recorder.uid ?? before.updatedBy);
        await _recorder.record(
          groupId: before.groupId,
          entity: SyncEntity.member,
          entityId: id,
          action: SyncAction.delete,
          before: _codec.member(before),
          after: _codec.member((await _memberDao.getMemberById(id))!),
        );
        return true;
      });
      if (!removed) return left(const MemberFailure.notFound());
      return right(unit);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, bool>> isMemberReferenced(String memberId) async {
    try {
      return right(await _memberDao.isMemberReferenced(memberId));
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  /// The account a member stays linked to: the signed-in account when it is
  /// me, nobody when the signed-in account lets it go, and otherwise
  /// whoever claimed it.
  String? _linkedUid(db.Member row, {required bool isMe}) {
    final uid = _recorder.uid;
    if (uid == null) return row.linkedUid;
    if (isMe) return uid;
    return row.linkedUid == uid ? null : row.linkedUid;
  }

  /// Makes every other member of the group "not me" before [exceptId]
  /// becomes me.
  Future<void> _releaseMe(String groupId, {required String exceptId}) async {
    final uid = _recorder.uid;
    for (final other in await _memberDao.getMembersByGroup(groupId)) {
      final isMine = other.isMe || (uid != null && other.linkedUid == uid);
      if (other.id == exceptId || !isMine) continue;
      await _memberDao.updateMemberById(db.MembersCompanion(
        id: Value(other.id),
        isMe: const Value(false),
        linkedUid: Value(_linkedUid(other, isMe: false)),
        updatedBy: Value(uid ?? other.updatedBy),
      ));
      await _recorder.record(
        groupId: groupId,
        entity: SyncEntity.member,
        entityId: other.id,
        action: SyncAction.update,
        before: _codec.member(other),
        after: _codec.member((await _memberDao.getMemberById(other.id))!),
      );
    }
  }
}
