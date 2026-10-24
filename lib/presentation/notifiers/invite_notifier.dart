import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

part 'invite_notifier.g.dart';

/// Sharing actions (R-3 P6). Methods return the use case result directly;
/// [state] only reflects loading for UI.
@riverpod
class InviteNotifier extends _$InviteNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Runs a use case as a tracked operation (R-4 AC8).
  Future<Either<Failure, T>> _run<T>(
    TelemetryEvent event,
    Future<Either<Failure, T>> Function() action,
  ) async {
    state = const AsyncLoading();
    final result = await trackOp(ref.read(trackEventProvider), event, action);
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
    return _run(TelemetryEvent.opGetInviteLink, () => useCase(groupId));
  }

  Future<Either<Failure, Uri>> resetInviteLink(String groupId) {
    final useCase = ref.read(resetInviteLinkProvider);
    return _run(TelemetryEvent.opResetInviteLink, () => useCase(groupId));
  }

  Future<Either<Failure, String>> joinGroup(String token) {
    final useCase = ref.read(joinGroupProvider);
    return _run(TelemetryEvent.opJoinGroup, () => useCase(token));
  }

  Future<Either<Failure, Unit>> leaveGroup(String groupId) {
    final useCase = ref.read(leaveGroupProvider);
    return _run(TelemetryEvent.opLeaveGroup, () => useCase(groupId));
  }
}
