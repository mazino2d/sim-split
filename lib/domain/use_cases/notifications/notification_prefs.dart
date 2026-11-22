import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/notification_failure.dart';
import 'package:simsplit/domain/repositories/notification_prefs_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// The account's notification choices (R-9 AC3, AC26–AC32).
class WatchNotificationPrefs
    implements StreamUseCase<NotificationPrefs, NoParams> {
  const WatchNotificationPrefs(
      {required NotificationPrefsRepository repository})
      : _repository = repository;

  final NotificationPrefsRepository _repository;

  @override
  Stream<Either<Failure, NotificationPrefs>> call(NoParams params) =>
      _repository.watchPrefs();
}

class SetNotificationCategoryParams {
  const SetNotificationCategoryParams(this.category, {required this.on});

  final NotificationCategory category;
  final bool on;
}

/// One switch in Settings → Notifications (AC3).
class SetNotificationCategory
    implements AsyncUseCase<Unit, SetNotificationCategoryParams> {
  const SetNotificationCategory(
      {required NotificationPrefsRepository repository})
      : _repository = repository;

  final NotificationPrefsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(SetNotificationCategoryParams params) =>
      _repository.setCategory(params.category, params.on);
}

/// One choice below the first Notifications screen (AC26–AC32).
sealed class NotificationPrefsChange {
  const NotificationPrefsChange();

  /// The choice, for the usage event's result (no IDs).
  String get usageResult;
}

/// A switch under Group activity → Notify me about (AC26).
final class ActivityEventChange extends NotificationPrefsChange {
  const ActivityEventChange(this.event, {required this.on});

  final ActivityEvent event;
  final bool on;

  @override
  String get usageResult => '${event.id}_${on ? 'on' : 'off'}';
}

/// "Only changes that involve me" (AC27).
final class OnlyInvolvingMeChange extends NotificationPrefsChange {
  const OnlyInvolvingMeChange({required this.on});

  final bool on;

  @override
  String get usageResult => on ? 'on' : 'off';
}

/// How often group activity is bundled (AC28).
final class BundleChange extends NotificationPrefsChange {
  const BundleChange(this.bundle);

  final ActivityBundle bundle;

  @override
  String get usageResult => 'bundle_${bundle.wire}';
}

/// One group's choice, from its menu or Settings → Groups (AC29).
final class GroupChange extends NotificationPrefsChange {
  const GroupChange(this.groupId, this.choice);

  final String groupId;
  final GroupNotifyChoice choice;

  @override
  String get usageResult => choice.wireName;
}

/// Pause all notifications, or resume with a null [choice] (AC30).
final class PauseChange extends NotificationPrefsChange {
  const PauseChange(this.choice);

  final PauseChoice? choice;

  @override
  String get usageResult => choice?.wireName ?? 'resume';
}

/// Longer quiet hours (AC31).
final class QuietHoursChange extends NotificationPrefsChange {
  const QuietHoursChange(this.quietHours);

  final QuietHours quietHours;

  @override
  String get usageResult => 'from_${quietHours.from.hhmm.replaceAll(':', '')}'
      '_to_${quietHours.to.hhmm.replaceAll(':', '')}';
}

/// Day, time and debt age of the settle reminder (AC32).
final class SettleReminderChange extends NotificationPrefsChange {
  const SettleReminderChange(this.settle);

  final SettleReminderPrefs settle;

  @override
  String get usageResult => 'day_${settle.day}'
      '_at_${settle.time.hhmm.replaceAll(':', '')}'
      '_min_${settle.minDays}d';
}

class UpdateNotificationPrefsParams {
  const UpdateNotificationPrefsParams(this.change, {this.current});

  final NotificationPrefsChange change;

  /// The choices as last seen, to refuse a group past [maxGroupSettings].
  final NotificationPrefs? current;
}

/// Saves one choice for every device of the account, refusing values the
/// screens never offer (AC26–AC32).
class UpdateNotificationPrefs
    implements AsyncUseCase<Unit, UpdateNotificationPrefsParams> {
  const UpdateNotificationPrefs({
    required NotificationPrefsRepository repository,
    DateTime Function() now = DateTime.now,
  })  : _repository = repository,
        _now = now;

  final NotificationPrefsRepository _repository;
  final DateTime Function() _now;

  @override
  Future<Either<Failure, Unit>> call(UpdateNotificationPrefsParams params) =>
      switch (params.change) {
        ActivityEventChange(:final event, :final on) =>
          _repository.setActivityEvent(event, on),
        OnlyInvolvingMeChange(:final on) => _repository.setOnlyInvolvingMe(on),
        BundleChange(:final bundle) => _repository.setBundle(bundle),
        GroupChange(:final groupId, :final choice) =>
          _setGroup(groupId, choice, params.current),
        PauseChange(:final choice) =>
          _repository.setPausedUntil(choice?.until(_now())),
        QuietHoursChange(:final quietHours) =>
          QuietHours.validFrom(quietHours.from) &&
                  QuietHours.validTo(quietHours.to)
              ? _repository.setQuietHours(quietHours)
              : Future.value(left(const NotificationFailure.invalidChoice())),
        SettleReminderChange(:final settle) => settle.day >= 0 &&
                settle.day <= 6 &&
                SettleReminderPrefs.validTime(settle.time) &&
                SettleReminderPrefs.minDaysChoices.contains(settle.minDays)
            ? _repository.setSettleReminder(settle)
            : Future.value(left(const NotificationFailure.invalidChoice())),
      };

  Future<Either<Failure, Unit>> _setGroup(String groupId,
      GroupNotifyChoice choice, NotificationPrefs? current) async {
    final setting = switch (choice) {
      GroupNotifyChoice.all => null,
      GroupNotifyChoice.involving =>
        const GroupNotifySetting(GroupNotifyMode.involving),
      GroupNotifyChoice.off => const GroupNotifySetting(GroupNotifyMode.off),
      GroupNotifyChoice.offUntilMorning =>
        GroupNotifySetting(GroupNotifyMode.off, offUntil: nextMorning(_now())),
    };
    final groups = current?.groups ?? const {};
    if (setting != null &&
        !groups.containsKey(groupId) &&
        groups.length >= maxGroupSettings) {
      return left(const NotificationFailure.tooManyMutedGroups());
    }
    return _repository.setGroup(groupId, setting);
  }
}

/// Moves groups muted before settings v2 (`mutedGroups`) into `groups` as
/// Off, once, so the per-group choices are the only ones written (AC29).
/// Does nothing when there is nothing to move.
class MigrateMutedGroups implements AsyncUseCase<Unit, NotificationPrefs> {
  const MigrateMutedGroups({required NotificationPrefsRepository repository})
      : _repository = repository;

  final NotificationPrefsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NotificationPrefs prefs) async {
    if (prefs.legacyMutedGroups.isEmpty) return right(unit);
    return _repository.migrateMutedGroups(
        prefs.legacyMutedGroups, prefs.groups);
  }
}
