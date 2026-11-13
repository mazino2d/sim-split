/// The chat or social app whose built-in browser shows the page, from the
/// browser's user agent, or `null` in a regular browser (#109).
///
/// Google blocks sign-in in these embedded browsers
/// (`403 disallowed_useragent`), popups don't open in them, and on iOS they
/// can lose the sign-in result. Invite links are mostly shared through chat
/// apps, so the sign-in screen asks the user to open the link in their
/// browser instead.
String? inAppBrowserName(String userAgent) {
  for (final (name, pattern) in _apps) {
    if (pattern.hasMatch(userAgent)) return name;
  }
  return null;
}

// Messenger before Facebook: Messenger's user agent also has FBAN/FBAV.
final _apps = [
  ('Zalo', RegExp('Zalo', caseSensitive: false)),
  ('Messenger', RegExp(r'FBAN/Messenger|MessengerForiOS|FB_IAB/MESSENGER')),
  ('Facebook', RegExp(r'FBAN|FBAV|FB_IAB|FBIOS')),
  ('Instagram', RegExp(r'Instagram')),
  ('TikTok', RegExp(r'musical_ly|BytedanceWebview|TikTok')),
  ('LINE', RegExp(r' Line/')),
  ('Telegram', RegExp(r'Telegram')),
];
