import 'package:simsplit/domain/entities/notifications/announcement.dart';
import 'package:simsplit/domain/entities/notifications/notification_category.dart';

/// A push notification the user tapped (R-9 AC8).
class NotificationOpen {
  const NotificationOpen({
    required this.messageId,
    required this.category,
    required this.route,
    this.source,
  });

  /// The sender's ID for the message, for the open count (AC24).
  final String? messageId;

  final NotificationCategory? category;

  /// The in-app path to open, already checked by [parseNotificationRoute];
  /// null when the message named none or an invalid one.
  final String? route;

  /// What sent it, from the message's `source` data: `trigger:<id>`,
  /// `schedule:<id>` or `campaign:<id>`, with config ids from `crm/`. Null
  /// when missing or in any other shape.
  final String? source;

  /// The usage-event result for opening it (AC24): the source as
  /// `<kind>_<id>` (`trigger_group_activity`), else the category id, else
  /// `unknown`. Never the message ID, which embeds a group ID.
  String get usageResult {
    final parts = source?.split(':');
    final fromSource = parts == null || parts.length != 2
        ? null
        : configIdResult(parts[0], parts[1]);
    return fromSource ?? category?.id ?? 'unknown';
  }
}

final _source =
    RegExp(r'^(trigger|schedule|campaign):[a-z0-9][a-z0-9_-]{1,62}$');

/// [source] when it is a valid message source, otherwise null.
String? parseNotificationSource(String? source) =>
    source != null && _source.hasMatch(source) ? source : null;

final _id =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// The in-app path a message's `route` names, or null unless it is exactly
/// one of the shapes the sender uses: `/groups/<groupId>`,
/// `/groups/<groupId>/expenses/<expenseId>` or `/groups/<groupId>/settle`,
/// with the app's IDs (lowercase UUIDs). Anything else is ignored, so a
/// message can never open an arbitrary screen.
String? parseNotificationRoute(String? route) {
  if (route == null || route.length > 100) return null;
  final parts = route.split('/');
  if (parts.length < 3 || parts[0] != '' || parts[1] != 'groups') return null;
  if (!_id.hasMatch(parts[2])) return null;
  return switch (parts.length) {
    3 => route,
    4 when parts[3] == 'settle' => route,
    5 when parts[3] == 'expenses' && _id.hasMatch(parts[4]) => route,
    _ => null,
  };
}
