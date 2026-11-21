/// One language's copy of an in-app banner.
class AnnouncementCopy {
  const AnnouncementCopy({required this.title, required this.body});

  final String title;
  final String body;
}

/// An in-app banner from a campaign in `crm/campaigns/` (R-9 AC12), read
/// from `announcements/{id}`. Its [id] is the campaign's config id, such as
/// `2026-12-01-new-version`, never user data.
class Announcement {
  const Announcement({
    required this.id,
    required this.copy,
    required this.endsAt,
  });

  final String id;

  /// Copy by language code (`en`, `vi`).
  final Map<String, AnnouncementCopy> copy;

  final DateTime endsAt;

  /// The copy in [languageCode], falling back to English.
  AnnouncementCopy? copyFor(String languageCode) =>
      copy[languageCode] ?? copy['en'];

  bool activeAt(DateTime now) => endsAt.isAfter(now);
}

/// The most announcements an account remembers as dismissed; the rules
/// allow no more. Announcements end within weeks, so the oldest go first.
const maxDismissedAnnouncements = 100;

/// The one banner to show (AC12: at most one at a time): the active,
/// undismissed announcement that ends first, then by id; null when none.
Announcement? pickAnnouncement(
  Iterable<Announcement> announcements,
  Set<String> dismissed,
  DateTime now,
) {
  final candidates = announcements
      .where((a) => a.activeAt(now) && !dismissed.contains(a.id))
      .toList()
    ..sort((a, b) {
      final byEnd = a.endsAt.compareTo(b.endsAt);
      return byEnd != 0 ? byEnd : a.id.compareTo(b.id);
    });
  return candidates.firstOrNull;
}

final _configId = RegExp(r'^[a-z0-9][a-z0-9_-]{1,62}$');

/// The usage-event result naming a config item, such as
/// `campaign_2026_12_01_new_version` for kind `campaign` and id
/// `2026-12-01-new-version`: the endpoint's name format (lowercase letters,
/// digits and `_`, at most 64 characters). Null for an id that isn't a
/// config id, so nothing else can reach telemetry.
String? configIdResult(String kind, String id) {
  if (!_configId.hasMatch(id)) return null;
  final result = '${kind}_${id.replaceAll('-', '_')}';
  return result.length <= 64 ? result : result.substring(0, 64);
}
