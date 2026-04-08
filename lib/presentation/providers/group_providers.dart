import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/use_cases/groups/get_group.dart';
import 'package:simsplit/domain/use_cases/members/list_members.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/core/di/injection.dart';

part 'group_providers.g.dart';

/// Reactive stream of all groups. Re-renders UI on any DB change.
@riverpod
Stream<List<Group>> groupList(Ref ref) {
  final useCase = ref.watch(listGroupsProvider);
  return useCase(const NoParams()).map(
    (either) => either.fold(
      (failure) => throw Exception(failure.toString()),
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
      (failure) => throw Exception(failure.toString()),
      (group) => group,
    ),
  );
}

/// Reactive stream of members for a group.
@riverpod
Stream<List<Member>> memberList(Ref ref, String groupId) {
  final useCase = ref.watch(listMembersProvider);
  return useCase(ListMembersParams(groupId: groupId)).map(
    (either) => either.fold(
      (failure) => throw Exception(failure.toString()),
      (members) => members,
    ),
  );
}
