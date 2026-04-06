import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/di/injection.dart';
import '../../domain/use_cases/groups/create_group.dart';
import '../../domain/use_cases/groups/delete_group.dart';
import '../../domain/use_cases/groups/update_group.dart';

part 'group_notifier.g.dart';

@riverpod
class GroupNotifier extends _$GroupNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> createGroup({
    required String name,
    required String currencyCode,
    String? emoji,
    int colorValue = 0xFF6200EE,
  }) async {
    state = const AsyncLoading();
    final useCase = ref.read(createGroupProvider);
    final result = await useCase(CreateGroupParams(
      name: name,
      currencyCode: currencyCode,
      emoji: emoji,
      colorValue: colorValue,
    ));

    return result.fold(
      (failure) {
        state = AsyncError(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncData(null);
        return true;
      },
    );
  }

  Future<bool> updateGroup({
    required String id,
    required String name,
    required String currencyCode,
    String? emoji,
    int? colorValue,
    bool? isArchived,
  }) async {
    state = const AsyncLoading();
    final useCase = ref.read(updateGroupProvider);
    final result = await useCase(UpdateGroupParams(
      id: id,
      name: name,
      currencyCode: currencyCode,
      emoji: emoji,
      colorValue: colorValue,
      isArchived: isArchived,
    ));

    return result.fold(
      (failure) {
        state = AsyncError(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncData(null);
        return true;
      },
    );
  }

  Future<bool> deleteGroup(String id) async {
    state = const AsyncLoading();
    final useCase = ref.read(deleteGroupProvider);
    final result = await useCase(DeleteGroupParams(id: id));

    return result.fold(
      (failure) {
        state = AsyncError(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncData(null);
        return true;
      },
    );
  }
}
