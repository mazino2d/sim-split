import 'dart:js_interop';

@JS('navigator.userAgent')
external String get _userAgent;

/// The browser name and major version for error reports, e.g. `Chrome 141`.
String deviceOs() {
  final ua = _userAgent;
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
