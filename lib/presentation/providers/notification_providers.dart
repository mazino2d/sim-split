import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show Locale;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_open.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
import 'package:simsplit/domain/entities/notifications/notification_setup.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/repositories/notification_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/presentation/providers/locale_provider.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

part 'notification_providers.g.dart';

/// Push on this install (R-9): what the system allows and what the user
/// chose. Unsupported without accounts. Invalidate it when it may have
/// changed (after asking, or when the app comes back from the system
/// settings).
@Riverpod(keepAlive: true)
Future<NotificationSetup> notificationSetup(Ref ref) async {
  if (!ref.watch(authAvailableProvider)) return NotificationSetup.unsupported;
  final result =
      await ref.watch(getNotificationSetupProvider)(const NoParams());
  return result.getOrElse((_) => NotificationSetup.unsupported);
}

/// The account's notification choices (R-9 AC3, AC4); defaults while
/// signed out or without accounts.
@riverpod
Stream<NotificationPrefs> notificationPrefs(Ref ref) {
  if (!ref.watch(authAvailableProvider)) {
    return Stream.value(const NotificationPrefs());
  }
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return Stream.value(const NotificationPrefs());
  return ref.watch(watchNotificationPrefsProvider)(const NoParams()).map(
        (either) => either.fold((f) => throw FailureException(f), (p) => p),
      );
}

/// The app's language code, `en` or `vi`.
String _languageCode(Ref ref) =>
    (ref.watch(localeProvider).value ?? deviceDefaultLocale()).languageCode;

/// Keeps this device registered for push while signed in, once the user
/// turned notifications on and the system allows them: on sign-in, on app
/// start, when the app language changes and when the push token changes.
/// Watch it once from the app root.
@Riverpod(keepAlive: true)
Future<void> deviceRegistrationRunner(Ref ref) async {
  if (!ref.watch(authAvailableProvider)) return;
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return;
  final setup = await ref.watch(notificationSetupProvider.future);
  if (!setup.active) return;
  final locale = _languageCode(ref);

  final register = ref.watch(registerDeviceProvider);
  final track = ref.watch(trackEventProvider);
  Future<void> run() async {
    final result = await trackOp(
        track, TelemetryEvent.opRegisterDevice, () => register(locale));
    result.fold((f) => debugPrint('[push] registration failed: $f'), (_) {});
  }

  final refreshes = ref
      .watch(watchTokenRefreshesProvider)(const NoParams())
      .listen((_) => run());
  ref.onDispose(refreshes.cancel);
  await run();
}

/// Names the Android notification channels in the app's language (AC5).
/// Watch it once from the app root.
@Riverpod(keepAlive: true)
Future<void> notificationChannels(Ref ref) async {
  if (!ref.watch(authAvailableProvider)) return;
  final l10n = lookupAppLocalizations(Locale(_languageCode(ref)));
  await ref.watch(setUpNotificationChannelsProvider)([
    for (final category in NotificationCategory.values)
      NotificationChannelSpec(
        category: category,
        name: notificationCategoryName(category, l10n),
        description: notificationCategoryDescription(category, l10n),
      ),
  ]);
}

/// The path of a tapped notification, waiting for the user to be signed in
/// before the app opens it (AC8).
@Riverpod(keepAlive: true)
class PendingNotificationRoute extends _$PendingNotificationRoute {
  @override
  String? build() => null;

  void set(String? route) => state = route;
}

/// Records every tapped notification and queues its route (AC8, AC24).
/// Watch it once from the app root.
@Riverpod(keepAlive: true)
void notificationOpenRunner(Ref ref) {
  if (!ref.watch(authAvailableProvider)) return;
  final track = ref.watch(trackEventProvider);
  final opens = ref
      .watch(watchNotificationOpensProvider)(const NoParams())
      .listen((either) => either.fold((_) {}, (open) {
            track(
                BreadcrumbKind.op, TelemetryEvent.opNotificationOpened.wireName,
                result: notificationOpenedResult(open));
            if (open.route != null) {
              ref
                  .read(pendingNotificationRouteProvider.notifier)
                  .set(open.route);
            }
          }));
  ref.onDispose(opens.cancel);
}

/// The usage event's result for a tapped notification:
/// `<category>__<messageId>`, in the endpoint's name format (lowercase
/// letters, digits and `_`, at most 64 characters).
String notificationOpenedResult(NotificationOpen open) {
  final category = open.category?.id ?? 'unknown';
  final id = (open.messageId ?? '')
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9_]'), '_');
  final result = id.isEmpty ? category : '${category}__$id';
  return result.length <= 64 ? result : result.substring(0, 64);
}

String notificationCategoryName(
        NotificationCategory category, AppLocalizations l10n) =>
    switch (category) {
      NotificationCategory.groupActivity =>
        l10n.notificationCategoryGroupActivity,
      NotificationCategory.settleReminder =>
        l10n.notificationCategorySettleReminder,
      NotificationCategory.updates => l10n.notificationCategoryUpdates,
    };

String notificationCategoryDescription(
        NotificationCategory category, AppLocalizations l10n) =>
    switch (category) {
      NotificationCategory.groupActivity =>
        l10n.notificationCategoryGroupActivityDescription,
      NotificationCategory.settleReminder =>
        l10n.notificationCategorySettleReminderDescription,
      NotificationCategory.updates =>
        l10n.notificationCategoryUpdatesDescription,
    };
