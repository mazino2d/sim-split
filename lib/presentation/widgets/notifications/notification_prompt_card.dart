import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/notifiers/notification_notifier.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/notification_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

/// The one time the app offers notifications (R-9 AC1): an inline line in
/// the first group a signed-in user opens that has another account in it,
/// never on launch and never a dialog. "Turn on" shows the system prompt;
/// whatever the answer, or "Not now", it never shows again on this install.
class NotificationPromptCard extends ConsumerWidget {
  const NotificationPromptCard({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(authAvailableProvider)) return const SizedBox.shrink();
    // Keeps the notifier alive while the prompt is open.
    final busy = ref.watch(notificationProvider).isLoading;
    final user = ref.watch(currentUserProvider).value;
    final group = ref.watch(liveGroupProvider(groupId)).value;
    final setup = ref.watch(notificationSetupProvider).value;
    final show = user != null &&
        group != null &&
        group.memberUids.length >= 2 &&
        setup != null &&
        setup.supported &&
        !setup.promptHandled &&
        !setup.active;
    if (!show) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final notifier = ref.read(notificationProvider.notifier);

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppTheme.gutter, 0, AppTheme.gutter, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_none_outlined,
                size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l10n.notificationPrompt,
                  style: theme.textTheme.bodySmall),
            ),
            TextButton(
              onPressed: context.tracked(TelemetryEvent.tapNotificationsNotNow,
                  busy ? null : notifier.notNow),
              child: Text(l10n.notNow),
            ),
            FilledButton.tonal(
              onPressed: context.tracked(TelemetryEvent.tapTurnOnNotifications,
                  busy ? null : notifier.turnOn),
              child: Text(l10n.notificationTurnOn),
            ),
          ],
        ),
      ),
    );
  }
}
