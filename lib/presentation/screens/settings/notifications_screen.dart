import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/notifiers/notification_notifier.dart';
import 'package:simsplit/presentation/providers/notification_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

/// Settings → Notifications (R-9 AC2, AC3): one switch per category with
/// its one-line description, saved with the account so every device
/// follows it. Above them, one calm line about this device: off until the
/// user turns notifications on here, or blocked in the system settings,
/// with where to allow them.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref,
      NotificationCategory category, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final result =
        await ref.read(notificationProvider.notifier).setCategory(category, on);
    result.fold(
      (failure) => messenger
          .showSnackBar(SnackBar(content: Text(failureMessage(failure, l10n)))),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Keeps the notifier alive while a change saves.
    final busy = ref.watch(notificationProvider).isLoading;
    final setup = ref.watch(notificationSetupProvider).value;
    final prefs = ref.watch(notificationPrefsProvider).value;

    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget? deviceLine;
    if (setup != null) {
      final String? text;
      if (!setup.supported) {
        text = l10n.notificationsUnsupported;
      } else if (!setup.optedIn) {
        text = l10n.notificationsOffOnDevice;
      } else if (setup.blockedBySystem) {
        text = kIsWeb
            ? l10n.notificationsBlockedWeb
            : l10n.notificationsBlockedAndroid;
      } else {
        text = null;
      }
      if (text != null) {
        deviceLine = Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.gutter, 16, AppTheme.gutter, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text(text, style: muted)),
              // After a refusal only the system settings can allow them.
              if (setup.supported && !setup.optedIn) ...[
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: context.tracked(
                      TelemetryEvent.tapTurnOnNotifications,
                      busy
                          ? null
                          : () =>
                              ref.read(notificationProvider.notifier).turnOn()),
                  child: Text(l10n.notificationTurnOn),
                ),
              ],
            ],
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifications)),
      body: ListView(
        children: [
          if (deviceLine != null) deviceLine,
          for (final category in NotificationCategory.values)
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
              title: Text(notificationCategoryName(category, l10n)),
              subtitle: Text(notificationCategoryDescription(category, l10n)),
              value: prefs?.isOn(category) ?? category.defaultOn,
              onChanged: context.trackedValue(
                  TelemetryEvent.tapNotificationCategory,
                  busy || prefs == null
                      ? null
                      : (on) => _set(context, ref, category, on)),
            ),
        ],
      ),
    );
  }
}
