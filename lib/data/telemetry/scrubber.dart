/// Removes personal data from error messages and stack traces before an
/// error report is queued (R-4 AC4). The endpoint scrubs again with the same
/// rules (services/telemetry/src/scrub.ts) as a second line of defence.
class Scrubber {
  const Scrubber();

  static final _rules = <(RegExp, String)>[
    // Emails.
    (RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), '<email>'),
    // Firestore document paths: groups/<id>/expenses/<id>, invites/<token>.
    (
      RegExp(
          r'''\b(groups|members|expenses|settlements|activity|invites|users)/[^\s/'")\]]+'''),
      r'$1/<id>'
    ),
    // UUIDs (local record IDs).
    (
      RegExp(
          r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b',
          caseSensitive: false),
      '<uuid>'
    ),
    // Firebase uids, Firestore auto IDs and invite tokens: long mixed runs.
    (
      RegExp(
          r'\b(?=[A-Za-z0-9_-]*[A-Za-z])(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9_-]{16,}\b'),
      '<id>'
    ),
    // Amounts and other numbers of 3+ digits, with separators. Line and
    // column numbers in stack traces (file.dart:123:45) follow a colon.
    (
      RegExp(
          r'(?<![:\d.,])\d{1,3}(?:[.,]\d{3})+(?![\d:])|(?<![:\d.,])\d{3,}(?![\d:])'),
      '<n>'
    ),
  ];

  /// Scrubs [text], also replacing any of [knownNames] (group and member
  /// names on this device, the account's name) that appear in it.
  String scrub(String text, {Iterable<String> knownNames = const []}) {
    var out = text;
    final names = knownNames.where((n) => n.trim().length >= 2).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final name in names) {
      out = out.replaceAll(
          RegExp(RegExp.escape(name.trim()), caseSensitive: false), '<name>');
    }
    for (final (pattern, replacement) in _rules) {
      out = out.replaceAllMapped(pattern, (m) {
        if (!replacement.contains(r'$1')) return replacement;
        return replacement.replaceAll(r'$1', m[1] ?? '');
      });
    }
    return out;
  }
}
