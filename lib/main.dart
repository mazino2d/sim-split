import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'package:simsplit/app.dart';
import 'package:simsplit/core/constants/firebase_emulators.dart';
import 'package:simsplit/firebase_options.dart';

var _urlStrategySet = false;

void main() async {
  // Must be called before anything else; also triggers font loading
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Keep native splash visible until we explicitly remove it,
  // so the first frame (with potentially unloaded icon fonts) is never shown.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Web URLs without '#', so invite links read simsplit.web.app/join/<token>.
  // It can be set only once, and the e2e journey calls main() per relaunch.
  if (!_urlStrategySet) {
    usePathUrlStrategy();
    _urlStrategySet = true;
  }

  await _initFirebase();

  runApp(
    const ProviderScope(
      child: SimSplitApp(),
    ),
  );
}

/// Connects to Firebase on Android, iOS and web (no network needed). A
/// failure must not stop the app from starting: it then stays local-only.
Future<void> _initFirebase() async {
  final options = DefaultFirebaseOptions.currentPlatform;
  // The e2e journey calls main() once per relaunch.
  if (options == null || Firebase.apps.isNotEmpty) return;
  final useEmulators = firebaseEmulatorHost.isNotEmpty;
  try {
    await Firebase.initializeApp(
      options: useEmulators
          ? options.copyWith(projectId: firebaseEmulatorProjectId)
          : options,
    );
  } on FirebaseException catch (e) {
    debugPrint('Firebase init failed: ${e.code} ${e.message}');
    return;
  }
  // Settings must be set before Firestore's first use. The offline cache is
  // off: Drift is the cache, and queued writes live in the outbox (R-3).
  // On web, long-polling replaces the streaming connection, which proxies
  // that inspect TLS (company networks, Cloudflare WARP) silently stall.
  final firestore = FirebaseFirestore.instance
    ..settings = const Settings(
      persistenceEnabled: false,
      webExperimentalForceLongPolling: true,
    );
  if (useEmulators) {
    await FirebaseAuth.instance
        .useAuthEmulator(firebaseEmulatorHost, firebaseAuthEmulatorPort);
    firestore.useFirestoreEmulator(firebaseEmulatorHost, firestoreEmulatorPort);
  }
}
