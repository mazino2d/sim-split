import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/domain/entities/activity_entry.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/use_cases/groups/get_group.dart';
import 'package:simsplit/domain/use_cases/members/list_members.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';

part 'group_providers.g.dart';

/// Reactive stream of all groups. Re-renders UI on any DB change.
@riverpod
Stream<List<Group>> groupList(Ref ref) {
  final useCase = ref.watch(listGroupsProvider);
  return useCase(const NoParams()).map(
    (either) => either.fold(
      (failure) => throw FailureException(failure),
      (groups) => groups,
    ),
  );
}

/// Single group detail, parameterized by groupId.
@riverpod
Future<Group> groupDetail(Ref ref, String groupId) {
  final useCase = ref.watch(getGroupProvider);
  return useCase(GetGroupParams(id: groupId)).then(
    (either) => either.fold(
      (failure) => throw FailureException(failure),
      (group) => group,
    ),
  );
}

/// A group as it changes, including sharing state pulled from the cloud.
/// Null once the group is gone (deleted, or left on another device).
@riverpod
Stream<Group?> liveGroup(Ref ref, String groupId) =>
    ref.watch(listGroupsProvider)(const NoParams()).map(
          (either) => either.fold(
            (failure) => throw FailureException(failure),
            (groups) => groups.where((g) => g.id == groupId).firstOrNull,
          ),
        );

/// Reactive stream of members for a group.
@riverpod
Stream<List<Member>> memberList(Ref ref, String groupId) {
  final useCase = ref.watch(listMembersProvider);
  return useCase(ListMembersParams(groupId: groupId)).map(
    (either) => either.fold(
      (failure) => throw FailureException(failure),
      (members) => members,
    ),
  );
}

/// A group's change history, newest first (R-3 AC25).
@riverpod
Stream<List<ActivityEntry>> activityList(Ref ref, String groupId) =>
    ref.watch(watchActivityProvider)(groupId).map(
          (either) => either.fold(
            (failure) => throw FailureException(failure),
            (entries) => entries,
          ),
        );
