// Firebase app config for the simsplit-as-se1-prd project.
//
// Generated from the Firebase Management API (the same values `flutterfire
// configure` writes). The API keys identify the app to Firebase and are not
// secrets: access is enforced by Firestore security rules and by key
// restrictions. Regenerate after adding or replacing a Firebase app.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  /// Options for the running platform, or null where online features are not
  /// supported (desktop).
  static FirebaseOptions? get currentPlatform {
    if (kIsWeb) return web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => null,
    };
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAgMmkLJn6-SuhP6zNiqDFtohgbputnOkI',
    appId: '1:113980760756:web:5e85a6f4f6e0a829592de1',
    messagingSenderId: '113980760756',
    projectId: 'simsplit-as-se1-prd',
    authDomain: 'simsplit-as-se1-prd.firebaseapp.com',
    storageBucket: 'simsplit-as-se1-prd.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC3XYeQu1vKiHp0H8X-WbGc_NQWI6UofnA',
    appId: '1:113980760756:android:56cad4c9ade84e99592de1',
    messagingSenderId: '113980760756',
    projectId: 'simsplit-as-se1-prd',
    storageBucket: 'simsplit-as-se1-prd.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB3nfBlFT501JRtKbokQn9Ef6Cx_3gJPcc',
    appId: '1:113980760756:ios:943647b96487d705592de1',
    messagingSenderId: '113980760756',
    projectId: 'simsplit-as-se1-prd',
    storageBucket: 'simsplit-as-se1-prd.firebasestorage.app',
    iosBundleId: 'com.mazino2d.simsplit',
  );
}
