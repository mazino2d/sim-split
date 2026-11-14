import 'package:fpdart/fpdart.dart' hide Group;
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class SetGroupArchivedParams {
  const SetGroupArchivedParams({required this.groupId, required this.archived});

  final String groupId;
  final bool archived;
}

/// Archives (closes) a group, or reopens it (#117). Only the owner can; a
/// group that hasn't synced yet has no owner and belongs to this device.
/// Archiving keeps everything: the group becomes read-only for every member.
class SetGroupArchived implements AsyncUseCase<Group, SetGroupArchivedParams> {
  const SetGroupArchived({
    required GroupRepository groupRepository,
    required AuthRepository authRepository,
  })  : _groupRepository = groupRepository,
        _authRepository = authRepository;

  final GroupRepository _groupRepository;
  final AuthRepository _authRepository;

  @override
  Future<Either<Failure, Group>> call(SetGroupArchivedParams params) async {
    final existing = await _groupRepository.getGroup(params.groupId);
    if (existing case Left(value: final failure)) return left(failure);
    final group = existing.toNullable()!;

    final owner = group.ownerUid;
    if (owner != null) {
      final user = await _authRepository.watchCurrentUser().first;
      if (user case Left(value: final failure)) return left(failure);
      if (user.toNullable()?.uid != owner) {
        return left(const GroupFailure.notOwner());
      }
    }
    if (group.isArchived == params.archived) return right(group);
    return _groupRepository.updateGroup(group.copyWith(
      isArchived: params.archived,
      updatedAt: DateTime.now(),
    ));
  }
}
