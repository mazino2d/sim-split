import 'package:fpdart/fpdart.dart' hide Group;
import '../entities/group.dart';
import '../failures/core_failure.dart';

abstract interface class GroupRepository {
  /// Reactive stream of all groups (including archived).
  Stream<Either<Failure, List<Group>>> watchGroups();

  Future<Either<Failure, Group>> getGroup(String id);
  Future<Either<Failure, Group>> createGroup(Group group);
  Future<Either<Failure, Group>> updateGroup(Group group);

  /// Hard-deletes the group and cascades to members, expenses, settlements.
  Future<Either<Failure, Unit>> deleteGroup(String id);
}
