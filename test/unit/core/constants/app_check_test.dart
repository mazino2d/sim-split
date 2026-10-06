import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/constants/app_check.dart';

void main() {
  AppCheckMode mode({
    bool isWeb = false,
    TargetPlatform platform = TargetPlatform.android,
    bool isRelease = true,
    bool useEmulators = false,
    String webSiteKey = 'site-key',
  }) =>
      appCheckModeFor(
        isWeb: isWeb,
        platform: platform,
        isRelease: isRelease,
        useEmulators: useEmulators,
        webSiteKey: webSiteKey,
      );

  test('is off against the emulators, whatever the platform', () {
    expect(mode(useEmulators: true), AppCheckMode.off);
    expect(mode(isWeb: true, useEmulators: true), AppCheckMode.off);
  });

  test('uses Play Integrity in Android release builds', () {
    expect(mode(), AppCheckMode.attested);
  });

  test('uses the debug provider in Android debug builds', () {
    expect(mode(isRelease: false), AppCheckMode.debug);
  });

  test('uses reCAPTCHA Enterprise in web release builds with a site key', () {
    expect(mode(isWeb: true), AppCheckMode.attested);
    expect(mode(isWeb: true, isRelease: false), AppCheckMode.debug);
  });

  test('is off in web release builds without a site key', () {
    expect(mode(isWeb: true, webSiteKey: ''), AppCheckMode.off);
  });

  test('uses the debug provider in web debug builds, site key or not', () {
    expect(
      mode(isWeb: true, isRelease: false, webSiteKey: ''),
      AppCheckMode.debug,
    );
  });

  test('is off on iOS until App Attest is set up', () {
    expect(mode(platform: TargetPlatform.iOS), AppCheckMode.off);
  });
}
