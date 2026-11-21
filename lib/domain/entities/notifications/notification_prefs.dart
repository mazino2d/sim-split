import 'package:simsplit/domain/entities/notifications/notification_category.dart';

/// The most groups an account can mute; the Firestore rules allow no more.
const maxMutedGroups = 200;

/// What the account wants to be notified about (R-9 AC3, AC4), kept in
/// `users/{uid}.notificationPrefs` so every device of the account and the
/// sender see the same choices. A missing field means the category's
/// default.
class NotificationPrefs {
  const NotificationPrefs({
    this.categories = const {},
    this.mutedGroups = const [],
  });

  /// Categories the user changed; the others keep their default.
  final Map<NotificationCategory, bool> categories;

  /// IDs of groups whose activity the user muted.
  final List<String> mutedGroups;

  bool isOn(NotificationCategory category) =>
      categories[category] ?? category.defaultOn;

  bool isMuted(String groupId) => mutedGroups.contains(groupId);

  @override
  bool operator ==(Object other) =>
      other is NotificationPrefs &&
      NotificationCategory.values.every((c) => isOn(c) == other.isOn(c)) &&
      mutedGroups.length == other.mutedGroups.length &&
      mutedGroups.every(other.mutedGroups.contains);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(NotificationCategory.values.map(isOn)),
        Object.hashAllUnordered(mutedGroups),
      );
}
