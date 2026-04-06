import 'package:fpdart/fpdart.dart' hide Group;
import '../../domain/entities/group.dart';
import '../../domain/failures/core_failure.dart';
import '../../domain/failures/group_failure.dart';
import '../../domain/repositories/group_repository.dart';
import '../daos/group_dao.dart';
import '../mappers/group_mapper.dart';

class DriftGroupRepository implements GroupRepository {
  const DriftGroupRepository({
    required GroupDao groupDao,
    required GroupMapper mapper,
  })  : _groupDao = groupDao,
        _mapper = mapper;

  final GroupDao _groupDao;
  final GroupMapper _mapper;

  @override
  Stream<Either<Failure, List<Group>>> watchGroups() {
    return _groupDao
        .watchAllGroups()
        .map((rows) => right<Failure, List<Group>>(
              rows.map(_mapper.toEntity).toList(),
            ))
        .handleError(
          (Object e) => left<Failure, List<Group>>(
            Failure.dbFailure(e.toString()),
          ),
        );
  }

  @override
  Future<Either<Failure, Group>> getGroup(String id) async {
    try {
      final row = await _groupDao.getGroupById(id);
      if (row == null) return left(const GroupFailure.notFound());
      return right(_mapper.toEntity(row));
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Group>> createGroup(Group group) async {
    try {
      await _groupDao.insertGroup(_mapper.toCompanion(group));
      return right(group);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Group>> updateGroup(Group group) async {
    try {
      final exists = await _groupDao.getGroupById(group.id);
      if (exists == null) return left(const GroupFailure.notFound());
      await _groupDao.updateGroupById(_mapper.toCompanion(group));
      return right(group);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteGroup(String id) async {
    try {
      await _groupDao.deleteGroupById(id);
      return right(unit);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }
}
