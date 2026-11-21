/// Whether the system lets the app show notifications.
enum NotificationPermission {
  granted,
  denied,

  /// The system has not asked yet (web). Android reports a permission it
  /// never asked for as [denied], so the app remembers asking itself.
  notAsked,
}

/// Push on this install (R-9 AC1, AC2): what the system allows and what the
/// user chose in the app.
class NotificationSetup {
  const NotificationSetup({
    required this.supported,
    required this.permission,
    required this.optedIn,
    required this.promptHandled,
  });

  /// Push works on this install: Android, or the web app when the build has
  /// a Web Push key. Never on iOS (on hold) or desktop.
  static const unsupported = NotificationSetup(
    supported: false,
    permission: NotificationPermission.denied,
    optedIn: false,
    promptHandled: true,
  );

  final bool supported;
  final NotificationPermission permission;

  /// The user tapped "Turn on" on this install (the card in a group, or
  /// Settings → Notifications). Only then is the device registered, so on
  /// systems that allow notifications without asking the user still chose
  /// them (Calm).
  final bool optedIn;

  /// The one-time card in a group was answered (turned on or "Not now"); it
  /// never shows again on this install.
  final bool promptHandled;

  /// Pushes reach this install.
  bool get active =>
      supported && optedIn && permission == NotificationPermission.granted;

  /// The user said yes but the system says no: Settings explains how to
  /// allow notifications in the system settings (AC2).
  bool get blockedBySystem =>
      supported && optedIn && permission != NotificationPermission.granted;
}

/// The result of asking for notifications, as the usage event records it.
enum NotificationPermissionOutcome {
  granted('granted'),
  denied('denied'),
  notNow('not_now');

  const NotificationPermissionOutcome(this.wireName);

  final String wireName;
}
