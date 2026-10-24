// Firebase app config for the simsplit-as-se1-dev project (APP_ENV=dev).
//
// Generated from the Firebase Management API (the same values `flutterfire
// configure --project simsplit-as-se1-dev` writes) for the apps that
// everything-as-code's terraform/gcp/simsplit-as-se1-dev creates. The API keys
// identify the app to Firebase and are not secrets: access is enforced by
// Firestore security rules, App Check and key restrictions. Regenerate after
// adding or replacing a Firebase app.
//
// iOS has no dev app: iOS builds use simsplit-as-se1-prd (APP_ENV=prd).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DevFirebaseOptions {
  /// Options for the running platform, or null where the dev project has no
  /// app (iOS, desktop).
  static FirebaseOptions? get currentPlatform {
    if (kIsWeb) return web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      _ => null,
    };
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCW7_HR_KpcgPu6V11aJRPLOSFFdiVX4dk',
    appId: '1:158855278019:web:71dee3bd1764e4ebe76176',
    messagingSenderId: '158855278019',
    projectId: 'simsplit-as-se1-dev',
    authDomain: 'simsplit-as-se1-dev.firebaseapp.com',
    storageBucket: 'simsplit-as-se1-dev.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBHmuzCYKUp_MksDmEDGRxgey8IpMJ-DdA',
    appId: '1:158855278019:android:ad6918d6e03ea9bfe76176',
    messagingSenderId: '158855278019',
    projectId: 'simsplit-as-se1-dev',
    storageBucket: 'simsplit-as-se1-dev.firebasestorage.app',
  );
}
