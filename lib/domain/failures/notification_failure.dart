import 'package:simsplit/domain/failures/core_failure.dart';

sealed class NotificationFailure extends Failure {
  const NotificationFailure(super.name);

  const factory NotificationFailure.tooManyMutedGroups() =
      NotificationTooManyMutedGroups;
}

/// The account already mutes as many groups as it can (R-9 AC4).
final class NotificationTooManyMutedGroups extends NotificationFailure {
  const NotificationTooManyMutedGroups()
      : super('notification_too_many_muted_groups');
}
