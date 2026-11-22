import 'package:simsplit/domain/entities/notifications/notification_category.dart';

/// The most groups whose notifications an account can change; the
/// Firestore rules allow no more.
const maxGroupSettings = 200;

/// A kind of change in a group, each with its own switch under Group
/// activity (R-9 AC26). Mirrors the `events` of `group_activity` in
/// `crm/categories.yaml`; `notification_categories_test.dart` keeps them
/// equal.
enum ActivityEvent {
  expenseCreate('expense_create', defaultOn: true),
  expenseUpdate('expense_update', defaultOn: true),
  expenseDelete('expense_delete', defaultOn: true),
  settlement('settlement', defaultOn: true),
  memberJoin('member_join', defaultOn: false);

  const ActivityEvent(this.id, {required this.defaultOn});

  /// The id in `crm/categories.yaml`; its camelCase form ([name]) is the
  /// key in `notificationPrefs.activityEvents`.
  final String id;

  final bool defaultOn;
}

/// How often group activity arrives, at most (R-9 AC28).
enum ActivityBundle {
  tenMinutes('10m'),
  thirtyMinutes('30m'),
  hour('1h'),
  daily('daily');

  const ActivityBundle(this.wire);

  /// The value in `notificationPrefs.bundle`.
  final String wire;

  static const fallback = ActivityBundle.tenMinutes;

  static ActivityBundle fromWire(Object? wire) =>
      values.where((b) => b.wire == wire).firstOrNull ?? fallback;
}

/// What one group notifies, as stored (R-9 AC29).
enum GroupNotifyMode {
  all('all'),
  involving('involving'),
  off('off');

  const GroupNotifyMode(this.wire);

  final String wire;

  static GroupNotifyMode? fromWire(Object? wire) =>
      values.where((m) => m.wire == wire).firstOrNull;
}

/// The four choices offered for a group, in the menu and in Settings (AC29).
enum GroupNotifyChoice {
  all,
  involving,
  offUntilMorning,
  off;

  /// Shown with a bell-off mark.
  bool get silenced => this == offUntilMorning || this == off;

  /// The snake_case name used as a usage result.
  String get wireName => switch (this) {
        all => 'all',
        involving => 'involving',
        offUntilMorning => 'off_until_morning',
        off => 'off',
      };
}

/// One group's stored setting: [mode], and for "Off until …" when it ends.
class GroupNotifySetting {
  const GroupNotifySetting(this.mode, {this.offUntil});

  final GroupNotifyMode mode;
  final DateTime? offUntil;

  /// The choice the user sees at [now]: an "Off until" that has passed is
  /// back to All activity.
  GroupNotifyChoice choiceAt(DateTime now) => switch (mode) {
        GroupNotifyMode.all => GroupNotifyChoice.all,
        GroupNotifyMode.involving => GroupNotifyChoice.involving,
        GroupNotifyMode.off => switch (offUntil) {
            null => GroupNotifyChoice.off,
            final until when until.isAfter(now) =>
              GroupNotifyChoice.offUntilMorning,
            _ => GroupNotifyChoice.all,
          },
      };

  @override
  bool operator ==(Object other) =>
      other is GroupNotifySetting &&
      other.mode == mode &&
      other.offUntil == offUntil;

  @override
  int get hashCode => Object.hash(mode, offUntil);
}

/// A time of day as minutes after midnight, written `HH:MM` in the prefs.
extension type const DayTime(int minutes) {
  static DayTime? parse(Object? hhmm) {
    if (hhmm is! String) return null;
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(hhmm);
    if (match == null) return null;
    return DayTime(int.parse(match[1]!) * 60 + int.parse(match[2]!));
  }

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  String get hhmm =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// When notifications wait for the morning (R-9 AC31). Only longer than
/// the default: [from] between 12:00 and 21:00, [to] between 08:00 and
/// 12:00.
class QuietHours {
  const QuietHours({this.from = defaultFrom, this.to = defaultTo});

  static const defaultFrom = DayTime(21 * 60);
  static const defaultTo = DayTime(8 * 60);
  static const earliestFrom = DayTime(12 * 60);
  static const latestTo = DayTime(12 * 60);

  final DayTime from;
  final DayTime to;

  bool get isDefault => from == defaultFrom && to == defaultTo;

  static bool validFrom(DayTime t) =>
      t.minutes >= earliestFrom.minutes && t.minutes <= defaultFrom.minutes;
  static bool validTo(DayTime t) =>
      t.minutes >= defaultTo.minutes && t.minutes <= latestTo.minutes;

  @override
  bool operator ==(Object other) =>
      other is QuietHours && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// When the weekly settle reminder comes and for which debts (R-9 AC32).
class SettleReminderPrefs {
  const SettleReminderPrefs({
    this.day = 0,
    this.time = defaultTime,
    this.minDays = 14,
  });

  static const defaultTime = DayTime(19 * 60);
  static const earliestTime = DayTime(8 * 60);
  static const latestTime = DayTime(21 * 60);
  static const minDaysChoices = [7, 14, 30];

  /// 0 = Sunday … 6 = Saturday.
  final int day;
  final DayTime time;

  /// How old a debt must be, in days: 7, 14 or 30.
  final int minDays;

  static bool validTime(DayTime t) =>
      t.minutes >= earliestTime.minutes && t.minutes <= latestTime.minutes;

  SettleReminderPrefs copyWith({int? day, DayTime? time, int? minDays}) =>
      SettleReminderPrefs(
        day: day ?? this.day,
        time: time ?? this.time,
        minDays: minDays ?? this.minDays,
      );

  @override
  bool operator ==(Object other) =>
      other is SettleReminderPrefs &&
      other.day == day &&
      other.time == time &&
      other.minDays == minDays;

  @override
  int get hashCode => Object.hash(day, time, minDays);
}

/// How long to pause all notifications (R-9 AC30).
enum PauseChoice {
  hour,
  untilMorning,
  week;

  /// When the pause ends if it starts at [now] (device time).
  DateTime until(DateTime now) => switch (this) {
        hour => now.add(const Duration(hours: 1)),
        untilMorning => nextMorning(now),
        week => now.add(const Duration(days: 7)),
      };

  String get wireName => switch (this) {
        hour => '1h',
        untilMorning => 'until_morning',
        week => '1w',
      };
}

/// The next 08:00 after [now], in [now]'s time zone: "until tomorrow
/// 08:00" for a pause or a group turned off.
DateTime nextMorning(DateTime now) {
  final today = DateTime(now.year, now.month, now.day, 8);
  return today.isAfter(now)
      ? today
      : DateTime(now.year, now.month, now.day + 1, 8);
}

/// What the account wants to be notified about (R-9 AC3, AC26–AC32), kept
/// in `users/{uid}.notificationPrefs` so every device of the account and
/// the sender see the same choices. A missing field means its default.
class NotificationPrefs {
  const NotificationPrefs({
    this.categories = const {},
    this.activityEvents = const {},
    this.onlyInvolvingMe = false,
    this.bundle = ActivityBundle.fallback,
    this.groups = const {},
    this.legacyMutedGroups = const [],
    this.pausedUntil,
    this.quietHours = const QuietHours(),
    this.settle = const SettleReminderPrefs(),
  });

  /// Categories the user changed; the others keep their default.
  final Map<NotificationCategory, bool> categories;

  /// Kinds of group change the user changed; the others keep their default.
  final Map<ActivityEvent, bool> activityEvents;

  final bool onlyInvolvingMe;
  final ActivityBundle bundle;

  /// Groups whose setting the user changed; a missing one is All activity.
  final Map<String, GroupNotifySetting> groups;

  /// Groups muted before settings v2 (`mutedGroups`); the app moves them
  /// into [groups] as Off.
  final List<String> legacyMutedGroups;

  final DateTime? pausedUntil;
  final QuietHours quietHours;
  final SettleReminderPrefs settle;

  bool isOn(NotificationCategory category) =>
      categories[category] ?? category.defaultOn;

  bool isEventOn(ActivityEvent event) =>
      activityEvents[event] ?? event.defaultOn;

  /// The group's choice as the user sees it at [now].
  GroupNotifyChoice groupChoice(String groupId, DateTime now) {
    final setting = groups[groupId];
    if (setting != null) return setting.choiceAt(now);
    return legacyMutedGroups.contains(groupId)
        ? GroupNotifyChoice.off
        : GroupNotifyChoice.all;
  }

  /// Whether the group shows the bell-off mark at [now].
  bool isGroupSilenced(String groupId, DateTime now) =>
      groupChoice(groupId, now).silenced;

  /// The end of the pause, or null when not paused at [now].
  DateTime? pausedAt(DateTime now) {
    final until = pausedUntil;
    return until != null && until.isAfter(now) ? until : null;
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationPrefs &&
      NotificationCategory.values.every((c) => isOn(c) == other.isOn(c)) &&
      ActivityEvent.values.every((e) => isEventOn(e) == other.isEventOn(e)) &&
      onlyInvolvingMe == other.onlyInvolvingMe &&
      bundle == other.bundle &&
      groups.length == other.groups.length &&
      groups.entries.every((e) => other.groups[e.key] == e.value) &&
      legacyMutedGroups.length == other.legacyMutedGroups.length &&
      legacyMutedGroups.every(other.legacyMutedGroups.contains) &&
      pausedUntil == other.pausedUntil &&
      quietHours == other.quietHours &&
      settle == other.settle;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(NotificationCategory.values.map(isOn)),
        Object.hashAll(ActivityEvent.values.map(isEventOn)),
        onlyInvolvingMe,
        bundle,
        Object.hashAllUnordered(
            groups.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAllUnordered(legacyMutedGroups),
        pausedUntil,
        quietHours,
        settle,
      );
}
