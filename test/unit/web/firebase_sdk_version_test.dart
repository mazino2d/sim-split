import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// web/firebase_sdk.js and web/firebase-messaging-sw.js load the Firebase JS
/// SDK themselves (R-8 P4: no inline scripts under the CSP), so their version
/// must be the one firebase_core_web is built against. A dependency update
/// that changes it fails here instead of in the browser.
void main() {
  test('the web Firebase JS SDK matches firebase_core_web', () {
    final config =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map<String, dynamic>;
    final package = (config['packages'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['name'] == 'firebase_core_web');
    // rootUri has no trailing slash; relative ones are relative to .dart_tool/.
    final rootUri = '${package['rootUri']}/';
    final root = Uri.parse('.dart_tool/')
        .resolve(rootUri)
        .resolve('lib/src/firebase_sdk_version.dart');
    final source = File.fromUri(
      root.isAbsolute ? root : Directory.current.uri.resolveUri(root),
    ).readAsStringSync();
    final supported = RegExp(r"supportedFirebaseJsSdkVersion = '([^']+)'")
        .firstMatch(source)!
        .group(1);

    final sdk = File('web/firebase_sdk.js').readAsStringSync();
    expect(
      RegExp(r"FIREBASE_JS_SDK_VERSION = '([^']+)'").firstMatch(sdk)?.group(1),
      supported,
      reason: 'web/firebase_sdk.js',
    );
    final sw = File('web/firebase-messaging-sw.js').readAsStringSync();
    final swVersions = RegExp(r'firebasejs/([0-9.]+)/')
        .allMatches(sw)
        .map((m) => m.group(1))
        .toSet();
    expect(swVersions, {supported}, reason: 'web/firebase-messaging-sw.js');
  });
}
