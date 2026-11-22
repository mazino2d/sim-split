import 'package:simsplit/domain/failures/core_failure.dart';

sealed class NotificationFailure extends Failure {
  const NotificationFailure(super.name);

  const factory NotificationFailure.tooManyMutedGroups() =
      NotificationTooManyMutedGroups;
  const factory NotificationFailure.invalidChoice() = NotificationInvalidChoice;
  const factory NotificationFailure.deviceNotRegistered() =
      NotificationDeviceNotRegistered;
}

/// The account already changed the notifications of as many groups as it
/// can (R-9 AC29).
final class NotificationTooManyMutedGroups extends NotificationFailure {
  const NotificationTooManyMutedGroups()
      : super('notification_too_many_muted_groups');
}

/// A value the screens never offer, such as shorter quiet hours (AC31).
final class NotificationInvalidChoice extends NotificationFailure {
  const NotificationInvalidChoice() : super('notification_invalid_choice');
}

/// This device doesn't get notifications, so a test can't reach it (AC33).
final class NotificationDeviceNotRegistered extends NotificationFailure {
  const NotificationDeviceNotRegistered()
      : super('notification_device_not_registered');
}
