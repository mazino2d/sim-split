import 'package:drift/drift.dart' show Value;
import 'package:fpdart/fpdart.dart' hide Group;
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';
import 'package:simsplit/data/daos/group_dao.dart';
import 'package:simsplit/data/mappers/group_mapper.dart';
import 'package:simsplit/data/sync/sync_codec.dart';
import 'package:simsplit/data/sync/sync_recorder.dart';
import 'package:simsplit/data/utils/stream_failure_transformer.dart';

class DriftGroupRepository implements GroupRepository {
  const DriftGroupRepository({
    required GroupDao groupDao,
    required GroupMapper mapper,
    required SyncRecorder recorder,
    SyncCodec codec = const SyncCodec(),
  })  : _groupDao = groupDao,
        _mapper = mapper,
        _recorder = recorder,
        _codec = codec;

  final GroupDao _groupDao;
  final GroupMapper _mapper;
  final SyncRecorder _recorder;
  final SyncCodec _codec;

  @override
  Stream<Either<Failure, List<Group>>> watchGroups() {
    return _groupDao
        .watchAllGroups()
        .map((rows) => right<Failure, List<Group>>(
              rows.map(_mapper.toEntity).toList(),
            ))
        .mapErrorsToDbFailure();
  }

  @override
  Future<Either<Failure, Group>> getGroup(String id) async {
    try {
      final row = await _groupDao.getGroupById(id);
      if (row == null || row.deleted) {
        return left(const GroupFailure.notFound());
      }
      return right(_mapper.toEntity(row));
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Group>> createGroup(Group group) async {
    try {
      await _groupDao.transaction(() async {
        final uid = _recorder.uid;
        await _groupDao.insertGroup(_mapper.toCompanion(group).copyWith(
              createdBy: Value(uid),
              updatedBy: Value(uid),
            ));
        await _recorder.record(
          groupId: group.id,
          entity: SyncEntity.group,
          entityId: group.id,
          action: SyncAction.create,
          after: _codec.group((await _groupDao.getGroupById(group.id))!),
        );
      });
      return right(group);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Group>> updateGroup(Group group) async {
    try {
      final updated = await _groupDao.transaction(() async {
        final before = await _groupDao.getGroupById(group.id);
        if (before == null || before.deleted) return false;
        await _groupDao.updateGroupById(_mapper
            .toCompanion(group)
            .copyWith(updatedBy: Value(_recorder.uid ?? before.updatedBy)));
        await _recorder.record(
          groupId: group.id,
          entity: SyncEntity.group,
          entityId: group.id,
          action: SyncAction.update,
          before: _codec.group(before),
          after: _codec.group((await _groupDao.getGroupById(group.id))!),
        );
        return true;
      });
      if (!updated) return left(const GroupFailure.notFound());
      return right(group);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteGroup(String id) async {
    try {
      await _groupDao.transaction(() async {
        final before = await _groupDao.getGroupById(id);
        if (before == null || before.deleted) return;
        await _groupDao.softDeleteGroup(id,
            updatedBy: _recorder.uid ?? before.updatedBy);
        await _recorder.record(
          groupId: id,
          entity: SyncEntity.group,
          entityId: id,
          action: SyncAction.delete,
          before: _codec.group(before),
          after: _codec.group((await _groupDao.getGroupById(id))!),
        );
      });
      return right(unit);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }
}
