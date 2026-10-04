import 'package:fpdart/fpdart.dart' hide Group;
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

abstract interface class GroupRepository {
  /// Reactive stream of all groups (including archived).
  Stream<Either<Failure, List<Group>>> watchGroups();

  Future<Either<Failure, Group>> getGroup(String id);
  Future<Either<Failure, Group>> createGroup(Group group);
  Future<Either<Failure, Group>> updateGroup(Group group);

  /// Soft-deletes the group (a tombstone that syncs). Its members, expenses
  /// and settlements are no longer shown.
  Future<Either<Failure, Unit>> deleteGroup(String id);
}
