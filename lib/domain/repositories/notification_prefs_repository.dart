import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

/// The account's notification choices (R-9 AC3, AC4), shared by all its
/// devices and read by the sender at send time.
abstract interface class NotificationPrefsRepository {
  /// The signed-in account's choices; defaults when it has none.
  Stream<Either<Failure, NotificationPrefs>> watchPrefs();

  Future<Either<Failure, Unit>> setCategory(
      NotificationCategory category, bool on);

  Future<Either<Failure, Unit>> setGroupMuted(String groupId, bool muted);
}
