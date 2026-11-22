import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

/// The account's notification choices (R-9 AC3, AC26–AC32), shared by all
/// its devices and read by the sender at send time.
abstract interface class NotificationPrefsRepository {
  /// The signed-in account's choices; defaults when it has none.
  Stream<Either<Failure, NotificationPrefs>> watchPrefs();

  Future<Either<Failure, Unit>> setCategory(
      NotificationCategory category, bool on);

  Future<Either<Failure, Unit>> setActivityEvent(ActivityEvent event, bool on);

  Future<Either<Failure, Unit>> setOnlyInvolvingMe(bool on);

  Future<Either<Failure, Unit>> setBundle(ActivityBundle bundle);

  /// Stores [setting] for [groupId]; null (All activity) removes the entry.
  Future<Either<Failure, Unit>> setGroup(
      String groupId, GroupNotifySetting? setting);

  /// Moves the groups muted before settings v2 into `groups` as Off,
  /// keeping any newer choice, and removes `mutedGroups`.
  Future<Either<Failure, Unit>> migrateMutedGroups(
      List<String> groupIds, Map<String, GroupNotifySetting> current);

  /// Pauses until [until]; null resumes.
  Future<Either<Failure, Unit>> setPausedUntil(DateTime? until);

  Future<Either<Failure, Unit>> setQuietHours(QuietHours quietHours);

  Future<Either<Failure, Unit>> setSettleReminder(SettleReminderPrefs settle);
}
