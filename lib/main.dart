import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'package:simsplit/app.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/constants/app_check.dart';
import 'package:simsplit/core/constants/firebase_emulators.dart';
import 'package:simsplit/domain/use_cases/telemetry/record_error.dart';
import 'package:simsplit/firebase_options.dart';

var _urlStrategySet = false;

void main() async {
  // Needed before plugins (native splash, Firebase) are used.
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

  final container = ProviderContainer();
  _reportUncaughtErrors(container);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SimSplitApp(),
    ),
  );
}

/// Sends uncaught errors as error reports (R-4 AC1), keeping Flutter's own
/// console output.
void _reportUncaughtErrors(ProviderContainer container) {
  void record(Object error, StackTrace? stack) => container.read(
      recordErrorProvider)(RecordErrorParams(error, stack, shownToUser: false));
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    record(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    record(error, stack);
    return true;
  };
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
  await _activateAppCheck(useEmulators: useEmulators);
}

/// Attaches an App Check token to Auth and Firestore requests, so the
/// project can reject requests that do not come from the genuine app. Both
/// enforce App Check, so without a token the backend rejects the app's
/// requests; a failure is only logged, so the app still opens on its local
/// data.
Future<void> _activateAppCheck({required bool useEmulators}) async {
  final mode = appCheckModeFor(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    isRelease: kReleaseMode,
    useEmulators: useEmulators,
    webSiteKey: recaptchaEnterpriseSiteKey,
  );
  if (mode == AppCheckMode.off) return;
  final attested = mode == AppCheckMode.attested;
  final debugToken = appCheckDebugToken.isEmpty ? null : appCheckDebugToken;
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: attested
          ? const AndroidPlayIntegrityProvider()
          : AndroidDebugProvider(debugToken: debugToken),
      providerWeb: kIsWeb
          ? (attested
              ? ReCaptchaEnterpriseProvider(recaptchaEnterpriseSiteKey)
              : WebDebugProvider(debugToken: debugToken))
          : null,
    );
  } on FirebaseException catch (e) {
    debugPrint('App Check activation failed: ${e.code} ${e.message}');
  }
}
