import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simsplit/app.dart';
import 'package:simsplit/firebase_options.dart';

void main() async {
  // Must be called before anything else; also triggers font loading
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Keep native splash visible until we explicitly remove it,
  // so the first frame (with potentially unloaded icon fonts) is never shown.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await _initFirebase();

  runApp(
    const ProviderScope(
      child: SimSplitApp(),
    ),
  );
}

/// Connects to Firebase on Android and iOS (no network needed). Nothing uses
/// it yet (R-3), so a failure must not stop the offline app from starting.
Future<void> _initFirebase() async {
  final options = DefaultFirebaseOptions.currentPlatform;
  if (options == null) return;
  try {
    await Firebase.initializeApp(options: options);
  } on FirebaseException catch (e) {
    debugPrint('Firebase init failed: ${e.code} ${e.message}');
  }
}
