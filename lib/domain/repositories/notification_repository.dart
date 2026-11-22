import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_open.dart';
import 'package:simsplit/domain/entities/notifications/notification_setup.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

/// A category's notification channel, named in the app's language (AC5).
class NotificationChannelSpec {
  const NotificationChannelSpec({
    required this.category,
    required this.name,
    required this.description,
  });

  final NotificationCategory category;
  final String name;
  final String description;
}

/// Push on this install (R-9): the system permission, this device's
/// registration with the account (`users/{uid}/devices/{deviceId}`) and the
/// notifications the user taps.
abstract interface class NotificationRepository {
  /// What the system allows and what the user chose on this install.
  Future<NotificationSetup> setup();

  /// Shows the system prompt and remembers that the user opted in and that
  /// the one-time card was answered, whatever the system says.
  Future<Either<Failure, NotificationPermission>> requestPermission();

  /// Remembers that the user said "Not now" to the one-time card.
  Future<Either<Failure, Unit>> dismissPrompt();

  /// Stores this device's push token, app language ([locale], `en` or `vi`),
  /// time zone and app version with the signed-in account; writes only when
  /// one of them changed since the last time.
  Future<Either<Failure, Unit>> registerDevice(String locale);

  /// Emits when the push token changes, so the device registers again.
  Stream<Unit> tokenRefreshes();

  /// Asks the sender for one test push to this device (AC33) by stamping
  /// `testRequestedAt` on its document. Fails with
  /// `NotificationFailure.deviceNotRegistered` when this device is not
  /// registered with the account.
  Future<Either<Failure, Unit>> requestTestNotification();

  /// Removes this device from the signed-in account (sign-out, AC23).
  Future<Either<Failure, Unit>> unregisterDevice();

  /// Removes every device of the signed-in account (account deletion, AC23).
  Future<Either<Failure, Unit>> deleteAllDevices();

  /// The notification that launched the app, if any (AC8).
  Future<NotificationOpen?> initialOpen();

  /// Notifications tapped while the app runs in the background (AC8).
  Stream<NotificationOpen> opens();

  /// Creates or renames one Android channel per category (AC5); does
  /// nothing elsewhere.
  Future<void> setUpChannels(List<NotificationChannelSpec> channels);
}
