// Firebase app config for the simsplit-as-se1-dev project (APP_ENV=dev).
//
// TODO(dev-env): every value below is a placeholder until everything-as-code
// applies terraform/gcp/simsplit-as-se1-dev. Replace them with the dev
// stack's Firebase app outputs (the Android app for com.mazino2d.simsplit.dev
// and the Web app: API key, app ID, messaging sender ID = project number),
// the same values `flutterfire configure --project simsplit-as-se1-dev`
// writes. While the API keys start with "TODO", [currentPlatform] returns
// null, so a dev build runs local-only instead of calling Firebase with
// made-up keys.
//
// iOS has no dev app: iOS builds use simsplit-as-se1-prd (APP_ENV=prd).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DevFirebaseOptions {
  /// Options for the running platform, or null where the dev project has no
  /// app (iOS, desktop) or the placeholders are not filled in yet.
  static FirebaseOptions? get currentPlatform {
    final options = kIsWeb
        ? web
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => android,
            _ => null,
          };
    if (options == null || options.apiKey.startsWith('TODO')) return null;
    return options;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'TODO-dev-web-api-key',
    appId: 'TODO-dev-web-app-id',
    messagingSenderId: 'TODO-dev-project-number',
    projectId: 'simsplit-as-se1-dev',
    authDomain: 'simsplit-as-se1-dev.firebaseapp.com',
    storageBucket: 'simsplit-as-se1-dev.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'TODO-dev-android-api-key',
    appId: 'TODO-dev-android-app-id',
    messagingSenderId: 'TODO-dev-project-number',
    projectId: 'simsplit-as-se1-dev',
    storageBucket: 'simsplit-as-se1-dev.firebasestorage.app',
  );
}
