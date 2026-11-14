import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';

/// Fails with [GroupFailure.archived] when [groupId] is archived: an archived
/// group is read-only for everyone until its owner reopens it (#117). Every
/// use case that changes members, expenses, settlements or the group's
/// settings checks it first.
Future<Either<Failure, Unit>> ensureGroupWritable(
  GroupRepository groups,
  String groupId,
) async {
  final result = await groups.getGroup(groupId);
  return result.flatMap((group) =>
      group.isArchived ? left(const GroupFailure.archived()) : right(unit));
}
