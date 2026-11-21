import 'package:fpdart/fpdart.dart' show Either, Unit;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_setup.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/notifications/notification_prefs.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/presentation/providers/notification_providers.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

part 'notification_notifier.g.dart';

/// Notification actions (R-9): asking for the permission, the switches in
/// Settings → Notifications and muting a group. Methods return the use
/// case result; [state] only reflects loading.
@riverpod
class NotificationNotifier extends _$NotificationNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<Either<Failure, T>> _run<T>(
    TelemetryEvent event,
    Future<Either<Failure, T>> Function() action, {
    String Function(T value)? successResult,
  }) async {
    state = const AsyncLoading();
    final result = await trackOp(ref.read(trackEventProvider), event, action,
        successResult: successResult);
    if (ref.mounted) {
      state = result.fold(
        (failure) => AsyncError(failure, StackTrace.current),
        (_) => const AsyncData(null),
      );
    }
    return result;
  }

  /// "Turn on": the system prompt (AC1). Registration follows once allowed.
  Future<Either<Failure, NotificationPermissionOutcome>> turnOn() async {
    final useCase = ref.read(requestNotificationPermissionProvider);
    final result = await _run(TelemetryEvent.opNotificationPermission,
        () => useCase(const NoParams()),
        successResult: (outcome) => outcome.wireName);
    ref.invalidate(notificationSetupProvider);
    return result;
  }

  /// "Not now" on the one-time card (AC1).
  Future<Either<Failure, NotificationPermissionOutcome>> notNow() async {
    final useCase = ref.read(dismissNotificationPromptProvider);
    final result = await _run(TelemetryEvent.opNotificationPermission,
        () => useCase(const NoParams()),
        successResult: (outcome) => outcome.wireName);
    ref.invalidate(notificationSetupProvider);
    return result;
  }

  Future<Either<Failure, Unit>> setCategory(
      NotificationCategory category, bool on) {
    final useCase = ref.read(setNotificationCategoryProvider);
    return _run(TelemetryEvent.opSetNotificationPref,
        () => useCase(SetNotificationCategoryParams(category, on: on)),
        successResult: (_) => '${category.id}_${on ? 'on' : 'off'}');
  }

  /// Hides a banner on every device of the account (AC12).
  Future<Either<Failure, Unit>> dismissAnnouncement(String id) {
    final useCase = ref.read(dismissAnnouncementProvider);
    return _run(TelemetryEvent.opDismissAnnouncement, () => useCase(id));
  }

  Future<Either<Failure, Unit>> setGroupMuted(String groupId, bool muted) {
    final useCase = ref.read(setGroupMutedProvider);
    final current = ref.read(notificationPrefsProvider).value;
    return _run(
        muted ? TelemetryEvent.opMuteGroup : TelemetryEvent.opUnmuteGroup,
        () => useCase(
            SetGroupMutedParams(groupId, muted: muted, current: current)));
  }
}
