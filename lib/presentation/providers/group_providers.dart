import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' hide Group;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/entities/group.dart';
import '../../domain/use_cases/groups/get_group.dart';
import '../../domain/use_cases/use_case.dart';
import '../../core/di/injection.dart';

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
