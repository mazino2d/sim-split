import 'dart:js_interop';

@JS('navigator.userAgent')
external String get _userAgent;

/// The browser's user agent; empty outside the web.
String userAgent() => _userAgent;
