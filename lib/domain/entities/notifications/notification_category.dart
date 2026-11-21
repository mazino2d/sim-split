/// A kind of push message (R-9): one switch in Settings → Notifications and
/// one Android notification channel. Mirrors `crm/categories.yaml`;
/// `test/unit/domain/notification_categories_test.dart` keeps them equal.
enum NotificationCategory {
  /// Friends' changes in the user's groups. On once notifications are
  /// allowed, mutable per group.
  groupActivity('group_activity', 'groupActivity', defaultOn: true),

  /// A weekly reminder of money owed for more than two weeks.
  settleReminder('settle_reminder', 'settleReminder', defaultOn: false),

  /// Rare notices from the maintainer.
  updates('updates', 'updates', defaultOn: false);

  const NotificationCategory(this.id, this.prefKey, {required this.defaultOn});

  /// The id in `crm/categories.yaml`, the Android channel id and the
  /// `category` of a message.
  final String id;

  /// The field in `users/{uid}.notificationPrefs`.
  final String prefKey;

  /// Whether the category is on when the user never changed it.
  final bool defaultOn;

  /// The category with [id], or null for an unknown one.
  static NotificationCategory? fromId(String? id) =>
      values.where((c) => c.id == id).firstOrNull;
}
