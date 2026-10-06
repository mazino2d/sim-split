import 'package:flutter/foundation.dart';

/// Site key of the reCAPTCHA Enterprise key that App Check uses on web, set
/// with `--dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=<key>`. Site keys are
/// public. Empty means App Check stays off on web.
const recaptchaEnterpriseSiteKey =
    String.fromEnvironment('RECAPTCHA_ENTERPRISE_SITE_KEY');

/// Debug token registered for App Check in everything-as-code, set with
/// `--dart-define=APP_CHECK_DEBUG_TOKEN=<uuid>` on debug builds. Empty means
/// the SDK makes up a token and prints it, to be registered by hand.
const appCheckDebugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

/// How the app proves to Firebase that a request comes from the genuine app
/// (R-3 P9). Enforcement is switched on in the Firebase project, not here.
enum AppCheckMode {
  /// No App Check: emulators, platforms without a provider yet.
  off,

  /// Debug provider: debug and profile builds. Uses [appCheckDebugToken]
  /// when it is set.
  debug,

  /// Platform attestation: Play Integrity on Android, reCAPTCHA Enterprise
  /// on web.
  attested,
}

/// Picks the App Check mode for this build.
///
/// iOS stays off until App Attest is set up with the Apple Developer account
/// (R-3 P8).
AppCheckMode appCheckModeFor({
  required bool isWeb,
  required TargetPlatform platform,
  required bool isRelease,
  required bool useEmulators,
  required String webSiteKey,
}) {
  if (useEmulators) return AppCheckMode.off;
  if (isWeb) {
    if (webSiteKey.isEmpty) return AppCheckMode.off;
    return isRelease ? AppCheckMode.attested : AppCheckMode.debug;
  }
  if (platform == TargetPlatform.android) {
    return isRelease ? AppCheckMode.attested : AppCheckMode.debug;
  }
  return AppCheckMode.off;
}
