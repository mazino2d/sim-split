import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

part 'invite_notifier.g.dart';

/// Sharing actions (R-3 P6). Methods return the use case result directly;
/// [state] only reflects loading for UI.
@riverpod
class InviteNotifier extends _$InviteNotifier {
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

  Future<Either<Failure, Uri>> inviteLink(String groupId) {
    final useCase = ref.read(getInviteLinkProvider);
    return _run(() => useCase(groupId));
  }

  Future<Either<Failure, Uri>> resetInviteLink(String groupId) {
    final useCase = ref.read(resetInviteLinkProvider);
    return _run(() => useCase(groupId));
  }

  Future<Either<Failure, String>> joinGroup(String token) {
    final useCase = ref.read(joinGroupProvider);
    return _run(() => useCase(token));
  }

  Future<Either<Failure, Unit>> leaveGroup(String groupId) {
    final useCase = ref.read(leaveGroupProvider);
    return _run(() => useCase(groupId));
  }
}
