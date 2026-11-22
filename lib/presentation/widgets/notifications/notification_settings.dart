import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
import 'package:simsplit/domain/use_cases/notifications/notification_prefs.dart';
import 'package:simsplit/presentation/notifiers/notification_notifier.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';

/// Saves one notification choice (R-9 AC26–AC32) and shows a failure, if
/// any, in a snackbar. The screen follows the saved choices.
Future<void> changeNotificationPrefs(
    BuildContext context, WidgetRef ref, NotificationPrefsChange change) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context)!;
  final result = await ref.read(notificationProvider.notifier).change(change);
  result.fold(
    (failure) => messenger
        .showSnackBar(SnackBar(content: Text(failureMessage(failure, l10n)))),
    (_) {},
  );
}

/// One pick among a few options, as radio rows (R-9 AC28–AC30, AC32).
class ChoiceList<T> extends StatelessWidget {
  const ChoiceList({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> options;
  final T? selected;
  final String Function(T option) label;

  /// Null while a change saves.
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<T>(
      groupValue: selected,
      onChanged: onChanged ?? (_) {}, // telemetry: callers track the pick
      child: Column(
        children: [
          for (final option in options)
            RadioListTile<T>(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppTheme.gutter - 4),
              value: option,
              enabled: onChanged != null,
              title: Text(label(option)),
            ),
        ],
      ),
    );
  }
}

/// A row of one-tap chips (R-9 AC31, AC32).
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.trailing = const [],
    this.fill = false,
  });

  final List<T> options;
  final T? selected;
  final String Function(T option) label;
  final ValueChanged<T>? onSelected;
  final List<Widget> trailing;

  /// One row of equal chips filling the width (the days of the week).
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chips = [
      for (final option in options)
        ChoiceChip(
          label: fill
              ? SizedBox(
                  width: double.infinity,
                  child: Text(label(option), textAlign: TextAlign.center))
              : Text(label(option)),
          padding: fill ? const EdgeInsets.symmetric(vertical: 8) : null,
          labelPadding: fill ? EdgeInsets.zero : null,
          labelStyle: TextStyle(
            color: option == selected ? cs.onPrimary : cs.onSurface,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          showCheckmark: false,
          selected: option == selected,
          onSelected: onSelected == null
              ? null
              : (_) => onSelected!(option), // telemetry: callers track it
        ),
    ];
    if (fill) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
        child: Row(
          children: [
            for (final (i, chip) in chips.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: chip),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...chips,
          ...trailing,
        ],
      ),
    );
  }
}

/// A muted line of explanation under a block of choices.
class ChoiceHint extends StatelessWidget {
  const ChoiceHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppTheme.gutter, 8, AppTheme.gutter, 16),
      child: Text(
        text,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

String dayTimeLabel(DayTime time) => time.hhmm;

String pauseChoiceLabel(PauseChoice? choice, AppLocalizations l10n) =>
    switch (choice) {
      null => l10n.pauseNone,
      PauseChoice.hour => l10n.pauseOneHour,
      PauseChoice.untilMorning => l10n.pauseUntilMorning,
      PauseChoice.week => l10n.pauseOneWeek,
    };

String groupChoiceLabel(GroupNotifyChoice choice, AppLocalizations l10n) =>
    switch (choice) {
      GroupNotifyChoice.all => l10n.groupModeAll,
      GroupNotifyChoice.involving => l10n.groupModeInvolving,
      GroupNotifyChoice.offUntilMorning => l10n.groupModeOffUntilMorning,
      GroupNotifyChoice.off => l10n.groupModeOff,
    };

String bundleLabel(ActivityBundle bundle, AppLocalizations l10n) =>
    switch (bundle) {
      ActivityBundle.tenMinutes => l10n.bundle10m,
      ActivityBundle.thirtyMinutes => l10n.bundle30m,
      ActivityBundle.hour => l10n.bundle1h,
      ActivityBundle.daily => l10n.bundleDaily,
    };

String bundleShortLabel(ActivityBundle bundle, AppLocalizations l10n) =>
    switch (bundle) {
      ActivityBundle.tenMinutes => l10n.bundleShort10m,
      ActivityBundle.thirtyMinutes => l10n.bundleShort30m,
      ActivityBundle.hour => l10n.bundleShort1h,
      ActivityBundle.daily => l10n.bundleShortDaily,
    };

String activityEventLabel(ActivityEvent event, AppLocalizations l10n) =>
    switch (event) {
      ActivityEvent.expenseCreate => l10n.notificationEventExpenseCreate,
      ActivityEvent.expenseUpdate => l10n.notificationEventExpenseUpdate,
      ActivityEvent.expenseDelete => l10n.notificationEventExpenseDelete,
      ActivityEvent.settlement => l10n.notificationEventSettlement,
      ActivityEvent.memberJoin => l10n.notificationEventMemberJoin,
    };

/// When a pause ends, relative to [now]: `13:45`, `08:00 tomorrow` or
/// `13:45, Nov 29`.
String pauseEndLabel(DateTime until, DateTime now, AppLocalizations l10n) {
  final time = DateFormat('HH:mm').format(until);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(until.year, until.month, until.day);
  final days = day.difference(today).inHours ~/ 24;
  if (days <= 0) return time;
  if (days == 1) return l10n.timeTomorrow(time);
  return l10n.timeOnDate(time, DateFormat.MMMd(l10n.localeName).format(until));
}
