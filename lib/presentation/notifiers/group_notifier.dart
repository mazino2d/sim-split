import 'package:fpdart/fpdart.dart' show Either, Unit;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/groups/create_group.dart';
import 'package:simsplit/domain/use_cases/groups/delete_group.dart';
import 'package:simsplit/domain/use_cases/groups/update_group.dart';

part 'group_notifier.g.dart';

/// Group mutations. Methods return the use case result directly; [state]
/// only reflects loading for UI (e.g. disabling Save).
@riverpod
class GroupNotifier extends _$GroupNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<Either<Failure, T>> _run<T>(
    Future<Either<Failure, T>> Function() action,
  ) async {
    state = const AsyncLoading();
    final result = await action();
    if (ref.mounted) {
      state = result.fold(
        (failure) => AsyncError(failure, StackTrace.current),
        (_) => const AsyncData(null),
      );
    }
    return result;
  }

  Future<Either<Failure, Group>> createGroup({
    required String name,
    required String currencyCode,
    String? emoji,
    int colorValue = 0xFF1976D2,
  }) {
    final useCase = ref.read(createGroupProvider);
    return _run(() => useCase(CreateGroupParams(
          name: name,
          currencyCode: currencyCode,
          emoji: emoji,
          colorValue: colorValue,
        )));
  }

  Future<Either<Failure, Group>> updateGroup({
    required String id,
    required String name,
    required String currencyCode,
    String? emoji,
    int? colorValue,
    bool? isArchived,
  }) {
    final useCase = ref.read(updateGroupProvider);
    return _run(() => useCase(UpdateGroupParams(
          id: id,
          name: name,
          currencyCode: currencyCode,
          emoji: emoji,
          colorValue: colorValue,
          isArchived: isArchived,
        )));
  }

  Future<Either<Failure, Unit>> deleteGroup(String id) {
    final useCase = ref.read(deleteGroupProvider);
    return _run(() => useCase(DeleteGroupParams(id: id)));
  }
}
