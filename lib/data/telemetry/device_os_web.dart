import 'package:simsplit/core/platform/user_agent.dart';
import 'package:simsplit/core/utils/in_app_browser.dart';

/// The browser name and major version for error reports, e.g. `Chrome 141`,
/// prefixed with the app for an in-app browser, e.g. `Zalo in-app browser`
/// (#109).
String deviceOs() {
  final ua = userAgent();
  final app = inAppBrowserName(ua);
  final browser = _browser(ua);
  return app == null ? browser : '$app in-app $browser';
}

String _browser(String ua) {
  for (final (name, pattern) in [
    ('Edge', RegExp(r'Edg/(\d+)')),
    ('Samsung Internet', RegExp(r'SamsungBrowser/(\d+)')),
    ('Chrome', RegExp(r'Chrome/(\d+)')),
    ('Firefox', RegExp(r'Firefox/(\d+)')),
    ('Safari', RegExp(r'Version/(\d+).*Safari')),
  ]) {
    final match = pattern.firstMatch(ua);
    if (match != null) return '$name ${match[1]}';
  }
  return 'browser';
}
