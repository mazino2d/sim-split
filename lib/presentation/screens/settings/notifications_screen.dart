import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
import 'package:simsplit/domain/entities/notifications/notification_setup.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/use_cases/notifications/notification_prefs.dart';
import 'package:simsplit/presentation/notifiers/notification_notifier.dart';
import 'package:simsplit/presentation/providers/notification_providers.dart';
import 'package:simsplit/presentation/router/app_routes.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/utils/tracking.dart';
import 'package:simsplit/presentation/widgets/common/section_label.dart';
import 'package:simsplit/presentation/widgets/notifications/notification_settings.dart';

/// Settings → Notifications (R-9 AC2, AC3, AC26–AC32): the entry point that
/// reads at a glance. Pause on top (with Resume while paused), one row per
/// category with a switch and its current choice as subtitle (Group
/// activity and Settle reminders open their detail), then quiet hours and
/// the per-group choices. At the bottom, one calm line about this device:
/// on, off until the user turns notifications on here, or blocked in the
/// system settings, with where to allow them.
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

  String _subtitle(NotificationCategory category, NotificationPrefs prefs,
      AppLocalizations l10n) {
    final on = prefs.isOn(category);
    switch (category) {
      case NotificationCategory.groupActivity:
        if (!on) return l10n.notificationOff;
        final events = ActivityEvent.values.where(prefs.isEventOn).toList();
        final defaults =
            ActivityEvent.values.where((e) => e.defaultOn).toList();
        final scope = prefs.onlyInvolvingMe
            ? l10n.activityScopeInvolving
            : events.length == defaults.length &&
                    events.every(defaults.contains)
                ? l10n.activityScopeAll
                : l10n.activityScopeCount(events.length);
        return l10n.groupActivitySubtitle(
            bundleShortLabel(prefs.bundle, l10n), scope);
      case NotificationCategory.settleReminder:
        final s = prefs.settle;
        return on
            ? l10n.settleReminderOnSubtitle(
                l10n.weekdayLong('${s.day}'), s.time.hhmm, s.minDays)
            : l10n.settleReminderOffSubtitle;
      case NotificationCategory.updates:
        return on ? l10n.updatesOnSubtitle : l10n.updatesOffSubtitle;
    }
  }

  String? _detailRoute(NotificationCategory category) => switch (category) {
        NotificationCategory.groupActivity => AppRoutes.notificationActivity,
        NotificationCategory.settleReminder => AppRoutes.notificationSettle,
        NotificationCategory.updates => null,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Keeps the notifier alive while a change saves.
    final busy = ref.watch(notificationProvider).isLoading;
    final setup = ref.watch(notificationSetupProvider).value;
    final prefs = ref.watch(notificationPrefsProvider).value;
    final now = ref.watch(notificationClockProvider)();
    final shown = prefs ?? const NotificationPrefs();
    final pausedUntil = shown.pausedAt(now);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    const padding = EdgeInsets.symmetric(horizontal: AppTheme.gutter);
    final changedGroups = shown.groups.keys
        .followedBy(shown.legacyMutedGroups)
        .toSet()
        .where((g) => shown.groupChoice(g, now) != GroupNotifyChoice.all)
        .length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifications)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (pausedUntil != null)
            _PausedCard(
              until: pauseEndLabel(pausedUntil, now, l10n),
              onResume: context.tracked(
                  TelemetryEvent.tapResumeNotifications,
                  busy || prefs == null
                      ? null
                      : () => changeNotificationPrefs(
                          context, ref, const PauseChange(null))),
            ),
          ListTile(
            contentPadding: padding,
            title: Text(l10n.pauseNotifications),
            subtitle: Text(pausedUntil == null
                ? l10n.pauseOff
                : l10n.pauseUntil(pauseEndLabel(pausedUntil, now, l10n))),
            trailing: const Icon(Icons.chevron_right),
            onTap: context.tracked(TelemetryEvent.tapOpenNotificationPause,
                () => context.push(AppRoutes.notificationPause)),
          ),
          SectionLabel(l10n.notificationKinds),
          for (final category in NotificationCategory.values)
            _CategoryRow(
              title: notificationCategoryName(category, l10n),
              subtitle: _subtitle(category, shown, l10n),
              on: shown.isOn(category),
              hasDetail: _detailRoute(category) != null,
              onOpen: context.tracked(
                  TelemetryEvent.tapOpenNotificationCategory,
                  switch (_detailRoute(category)) {
                    final route? => () => context.push(route),
                    // Without a detail, the row toggles its switch.
                    null => busy || prefs == null
                        ? null
                        : () =>
                            _set(context, ref, category, !shown.isOn(category)),
                  }),
              onChanged: context.trackedValue(
                  TelemetryEvent.tapNotificationCategory,
                  busy || prefs == null
                      ? null
                      : (on) => _set(context, ref, category, on)),
            ),
          const Divider(indent: AppTheme.gutter, endIndent: AppTheme.gutter),
          ListTile(
            contentPadding: padding,
            title: Text(l10n.quietHours),
            subtitle: Text(l10n.quietHoursSubtitle(
                '${shown.quietHours.from.hhmm} – ${shown.quietHours.to.hhmm}')),
            trailing: const Icon(Icons.chevron_right),
            onTap: context.tracked(TelemetryEvent.tapOpenQuietHours,
                () => context.push(AppRoutes.notificationQuietHours)),
          ),
          ListTile(
            contentPadding: padding,
            title: Text(l10n.groupNotifications),
            subtitle: Text(changedGroups == 0
                ? l10n.groupNotificationsAllDefault
                : l10n.groupNotificationsChanged(changedGroups)),
            trailing: const Icon(Icons.chevron_right),
            onTap: context.tracked(TelemetryEvent.tapOpenGroupNotificationsList,
                () => context.push(AppRoutes.notificationGroups)),
          ),
          if (setup != null) ...[
            const Divider(indent: AppTheme.gutter, endIndent: AppTheme.gutter),
            _DeviceLine(
              setup: setup,
              style: muted,
              onTurnOn: context.tracked(
                  TelemetryEvent.tapTurnOnNotifications,
                  busy
                      ? null
                      : () => ref.read(notificationProvider.notifier).turnOn()),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Paused until 08:00 tomorrow · Resume" on top while paused (AC30).
class _PausedCard extends StatelessWidget {
  const _PausedCard({required this.until, required this.onResume});

  final String until;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppTheme.gutter, 16, AppTheme.gutter, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          child: Row(
            children: [
              const Icon(Icons.pause),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.pausedBanner(until))),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onResume,
                child: Text(l10n.resumeNotifications),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A category: tap the text for its detail, or flip its switch (AC3).
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.title,
    required this.subtitle,
    required this.on,
    required this.hasDetail,
    required this.onOpen,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool on;
  final bool hasDetail;
  final VoidCallback? onOpen;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: ListTile(
            contentPadding:
                const EdgeInsets.only(left: AppTheme.gutter, right: 8),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: hasDetail ? const Icon(Icons.chevron_right) : null,
            onTap: onOpen,
          ),
        ),
        SizedBox(height: 32, child: VerticalDivider(color: cs.outlineVariant)),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: AppTheme.gutter - 4),
          child: Switch(value: on, onChanged: onChanged),
        ),
      ],
    );
  }
}

/// One calm line about this device (AC2), with Turn on when it was never
/// asked here.
class _DeviceLine extends StatelessWidget {
  const _DeviceLine({
    required this.setup,
    required this.style,
    required this.onTurnOn,
  });

  final NotificationSetup setup;
  final TextStyle? style;
  final VoidCallback? onTurnOn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final String text;
    if (!setup.supported) {
      text = l10n.notificationsUnsupported;
    } else if (!setup.optedIn) {
      text = l10n.notificationsOffOnDevice;
    } else if (setup.blockedBySystem) {
      text = kIsWeb
          ? l10n.notificationsBlockedWeb
          : l10n.notificationsBlockedAndroid;
    } else {
      text = l10n.notificationsOnOnDevice;
    }
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppTheme.gutter, 8, AppTheme.gutter, 8),
      child: Row(
        children: [
          Icon(
            setup.active ? Icons.check : Icons.info_outline,
            size: 18,
            color: style?.color,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: style)),
          // After a refusal only the system settings can allow them.
          if (setup.supported && !setup.optedIn) ...[
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: onTurnOn,
              child: Text(l10n.notificationTurnOn),
            ),
          ],
        ],
      ),
    );
  }
}
