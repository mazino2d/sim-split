import 'package:intl/intl.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';

/// "just now", "5 min ago", "3 h ago", then the date.
String relativeTime(
  DateTime time,
  AppLocalizations l10n,
  String locale, {
  DateTime? now,
}) {
  final elapsed = (now ?? DateTime.now()).difference(time);
  if (elapsed.inMinutes < 1) return l10n.justNow;
  if (elapsed.inHours < 1) return l10n.minutesAgo(elapsed.inMinutes);
  if (elapsed.inDays < 1) return l10n.hoursAgo(elapsed.inHours);
  return DateFormat('d MMM yyyy', locale).format(time.toLocal());
}
