import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/use_cases/notifications/notification_prefs.dart';
import 'package:simsplit/presentation/notifiers/notification_notifier.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/notification_providers.dart';
import 'package:simsplit/presentation/router/app_routes.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/tracking.dart';
import 'package:simsplit/presentation/widgets/common/section_label.dart';
import 'package:simsplit/presentation/widgets/groups/group_card.dart';
import 'package:simsplit/presentation/widgets/notifications/notification_settings.dart';

/// The screens one level below Settings → Notifications (R-9 AC26–AC32).
/// Each saves a choice as soon as it is picked, for every device of the
/// account, and shows the saved choices.

/// Whether a change is saving, keeping the notifier alive meanwhile, and
/// the account's current choices (defaults until they load).
(bool busy, NotificationPrefs? prefs) _watch(WidgetRef ref) => (
      ref.watch(notificationProvider).isLoading,
      ref.watch(notificationPrefsProvider).value,
    );

const _rowPadding = EdgeInsets.symmetric(horizontal: AppTheme.gutter);

/// Pause all notifications: 1 hour, until 08:00 tomorrow or 1 week (AC30).
class NotificationPauseScreen extends ConsumerStatefulWidget {
  const NotificationPauseScreen({super.key});

  @override
  ConsumerState<NotificationPauseScreen> createState() =>
      _NotificationPauseScreenState();
}

class _NotificationPauseScreenState
    extends ConsumerState<NotificationPauseScreen> {
  /// Only the end is stored, so the length is known once picked here; a
  /// pause set on another device selects nothing.
  _PauseOption? _picked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (busy, prefs) = _watch(ref);
    final now = ref.watch(notificationClockProvider)();
    final pausedUntil = prefs?.pausedAt(now);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.pauseNotifications)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          ChoiceList<_PauseOption>(
            options: _PauseOption.values,
            selected: pausedUntil == null ? _PauseOption.none : _picked,
            label: (option) => pauseChoiceLabel(option.choice, l10n),
            onChanged: context.trackedValue(
                TelemetryEvent.tapPickNotificationPause,
                busy || prefs == null
                    ? null
                    : (option) {
                        if (option == null) return;
                        setState(() => _picked = option);
                        changeNotificationPrefs(
                            context, ref, PauseChange(option.choice));
                      }),
          ),
          if (pausedUntil != null)
            ChoiceHint(
                l10n.pausedBanner(pauseEndLabel(pausedUntil, now, l10n))),
          ChoiceHint(l10n.pauseExplanation),
        ],
      ),
    );
  }
}

enum _PauseOption {
  none(null),
  hour(PauseChoice.hour),
  untilMorning(PauseChoice.untilMorning),
  week(PauseChoice.week);

  const _PauseOption(this.choice);

  /// Null is "Don't pause", which resumes.
  final PauseChoice? choice;
}

/// Group activity: one switch per kind of change, "Only changes that
/// involve me" and how often changes are bundled (AC26–AC28).
class GroupActivitySettingsScreen extends ConsumerWidget {
  const GroupActivitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final (busy, prefs) = _watch(ref);
    final shown = prefs ?? const NotificationPrefs();
    final disabled = busy || prefs == null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationCategoryGroupActivity)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SectionLabel(l10n.notifyMeAbout),
          for (final event in ActivityEvent.values)
            SwitchListTile(
              contentPadding: _rowPadding,
              title: Text(activityEventLabel(event, l10n)),
              value: shown.isEventOn(event),
              onChanged: context.trackedValue(
                  TelemetryEvent.tapNotificationEvent,
                  disabled
                      ? null
                      : (on) => changeNotificationPrefs(
                          context, ref, ActivityEventChange(event, on: on))),
            ),
          const Divider(indent: AppTheme.gutter, endIndent: AppTheme.gutter),
          SwitchListTile(
            contentPadding: _rowPadding,
            title: Text(l10n.onlyInvolvingMe),
            subtitle: Text(l10n.onlyInvolvingMeHint),
            value: shown.onlyInvolvingMe,
            onChanged: context.trackedValue(
                TelemetryEvent.tapOnlyInvolvingMe,
                disabled
                    ? null
                    : (on) => changeNotificationPrefs(
                        context, ref, OnlyInvolvingMeChange(on: on))),
          ),
          SectionLabel(l10n.bundleSection),
          ChoiceList<ActivityBundle>(
            options: ActivityBundle.values,
            selected: shown.bundle,
            label: (bundle) => bundleLabel(bundle, l10n),
            onChanged: context.trackedValue(
                TelemetryEvent.tapPickNotificationBundle,
                disabled
                    ? null
                    : (bundle) => bundle == null
                        ? null
                        : changeNotificationPrefs(
                            context, ref, BundleChange(bundle))),
          ),
          ChoiceHint(l10n.bundleExplanation),
        ],
      ),
    );
  }
}

/// Settle reminders: the day, the time and how old a debt must be (AC32).
class SettleReminderSettingsScreen extends ConsumerWidget {
  const SettleReminderSettingsScreen({super.key});

  static const _times = [
    DayTime(8 * 60),
    DayTime(12 * 60),
    DayTime(19 * 60),
    DayTime(20 * 60 + 30),
  ];

  Future<void> _pickOtherTime(
      BuildContext context, WidgetRef ref, SettleReminderPrefs settle) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: settle.time.hour, minute: settle.time.minute),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked == null || !context.mounted) return;
    final time = DayTime(picked.hour * 60 + picked.minute);
    if (!SettleReminderPrefs.validTime(time)) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.settleReminderTimeOutOfRange)));
      return;
    }
    await changeNotificationPrefs(
        context, ref, SettleReminderChange(settle.copyWith(time: time)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final (busy, prefs) = _watch(ref);
    final settle = (prefs ?? const NotificationPrefs()).settle;
    final disabled = busy || prefs == null;
    final times = [
      ..._times,
      if (!_times.contains(settle.time)) settle.time,
    ]..sort((a, b) => a.minutes.compareTo(b.minutes));

    void save(SettleReminderPrefs next) =>
        changeNotificationPrefs(context, ref, SettleReminderChange(next));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationCategorySettleReminder)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SectionLabel(l10n.settleReminderDay),
          ChoiceChips<int>(
            options: const [0, 1, 2, 3, 4, 5, 6],
            fill: true,
            selected: settle.day,
            label: (day) => l10n.weekdayShort('$day'),
            onSelected: context.trackedValue(TelemetryEvent.tapPickSettleDay,
                disabled ? null : (day) => save(settle.copyWith(day: day))),
          ),
          SectionLabel(l10n.settleReminderTime),
          ChoiceChips<DayTime>(
            options: times,
            selected: settle.time,
            label: dayTimeLabel,
            onSelected: context.trackedValue(TelemetryEvent.tapPickSettleTime,
                disabled ? null : (time) => save(settle.copyWith(time: time))),
            trailing: [
              ActionChip(
                label: Text(l10n.settleReminderOtherTime),
                onPressed: context.tracked(
                    TelemetryEvent.tapPickSettleTime,
                    disabled
                        ? null
                        : () => _pickOtherTime(context, ref, settle)),
              ),
            ],
          ),
          SectionLabel(l10n.settleReminderDebtAge),
          ChoiceList<int>(
            options: SettleReminderPrefs.minDaysChoices,
            selected: settle.minDays,
            label: (days) => days == const SettleReminderPrefs().minDays
                ? l10n.settleReminderDaysDefault(days)
                : l10n.settleReminderDays(days),
            onChanged: context.trackedValue(
                TelemetryEvent.tapPickSettleDebtAge,
                disabled
                    ? null
                    : (days) => days == null
                        ? null
                        : save(settle.copyWith(minDays: days))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.gutter, 16, AppTheme.gutter, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${l10n.settleReminderExampleLabel} '),
                    TextSpan(
                      text: l10n.settleReminderExampleTitle,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: '\n${l10n.settleReminderExampleBody}'),
                  ]),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet hours, only longer than 21:00–08:00 (AC31).
class QuietHoursScreen extends ConsumerWidget {
  const QuietHoursScreen({super.key});

  static const _starts = [DayTime(19 * 60), DayTime(20 * 60), DayTime(21 * 60)];
  static const _ends = [DayTime(8 * 60), DayTime(9 * 60), DayTime(10 * 60)];

  static List<DayTime> _with(List<DayTime> options, DayTime current) => [
        ...options,
        if (!options.contains(current)) current,
      ]..sort((a, b) => a.minutes.compareTo(b.minutes));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final (busy, prefs) = _watch(ref);
    final quiet = (prefs ?? const NotificationPrefs()).quietHours;
    final disabled = busy || prefs == null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.quietHours)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SectionLabel(l10n.quietHoursStart),
          ChoiceChips<DayTime>(
            options: _with(_starts, quiet.from),
            selected: quiet.from,
            label: dayTimeLabel,
            onSelected: context.trackedValue(
                TelemetryEvent.tapPickQuietHoursStart,
                disabled
                    ? null
                    : (from) => changeNotificationPrefs(
                        context,
                        ref,
                        QuietHoursChange(
                            QuietHours(from: from, to: quiet.to)))),
          ),
          SectionLabel(l10n.quietHoursEnd),
          ChoiceChips<DayTime>(
            options: _with(_ends, quiet.to),
            selected: quiet.to,
            label: dayTimeLabel,
            onSelected: context.trackedValue(
                TelemetryEvent.tapPickQuietHoursEnd,
                disabled
                    ? null
                    : (to) => changeNotificationPrefs(
                        context,
                        ref,
                        QuietHoursChange(
                            QuietHours(from: quiet.from, to: to)))),
          ),
          const SizedBox(height: 8),
          ChoiceHint(l10n.quietHoursExplanation),
        ],
      ),
    );
  }
}

/// Groups shared with other accounts, the only ones that notify (AC29).
List<Group> _sharedGroups(WidgetRef ref) {
  final uid = ref.watch(currentUserProvider).value?.uid;
  final groups = ref.watch(groupListProvider).value ?? const <Group>[];
  return [
    for (final g in groups)
      if (!g.isArchived && g.memberUids.any((u) => u != uid)) g,
  ];
}

/// Settings → Notifications → By group: each shared group with its choice
/// and a bell-off mark when it is off (AC29).
class GroupNotificationsListScreen extends ConsumerWidget {
  const GroupNotificationsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final (_, prefs) = _watch(ref);
    final shown = prefs ?? const NotificationPrefs();
    final now = ref.watch(notificationClockProvider)();
    final groups = _sharedGroups(ref);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.groupNotifications)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          for (final group in groups)
            ListTile(
              contentPadding: _rowPadding,
              leading: GroupGlyph(group: group, size: 44),
              title: Text(group.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  groupChoiceLabel(shown.groupChoice(group.id, now), l10n)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (shown.isGroupSilenced(group.id, now))
                    Icon(Icons.notifications_off_outlined,
                        size: 20,
                        color: cs.onSurfaceVariant,
                        semanticLabel: l10n.groupMuted),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: context.tracked(TelemetryEvent.tapOpenGroupNotifications,
                  () => context.push(AppRoutes.groupNotificationsOf(group.id))),
            ),
          ChoiceHint(groups.isEmpty
              ? l10n.groupNotificationsEmpty
              : l10n.groupNotificationsHint),
        ],
      ),
    );
  }
}

/// One group's notifications, from its menu or from By group (AC29).
class GroupNotificationsScreen extends ConsumerWidget {
  const GroupNotificationsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final (busy, prefs) = _watch(ref);
    final now = ref.watch(notificationClockProvider)();
    final group = ref.watch(liveGroupProvider(groupId)).value;
    final choice =
        (prefs ?? const NotificationPrefs()).groupChoice(groupId, now);

    return Scaffold(
      appBar: AppBar(
        title: Text(group?.name ?? l10n.notifications,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SectionLabel(l10n.groupNotificationsSection),
          ChoiceList<GroupNotifyChoice>(
            options: GroupNotifyChoice.values,
            selected: choice,
            label: (c) => groupChoiceLabel(c, l10n),
            onChanged: context.trackedValue(
                TelemetryEvent.tapPickGroupNotifications,
                busy || prefs == null
                    ? null
                    : (c) => c == null
                        ? null
                        : changeNotificationPrefs(
                            context, ref, GroupChange(groupId, c))),
          ),
        ],
      ),
    );
  }
}
