import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simsplit/app.dart';

void main() async {
  // Must be called before anything else; also triggers font loading
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Keep native splash visible until we explicitly remove it,
  // so the first frame (with potentially unloaded icon fonts) is never shown.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  runApp(
    const ProviderScope(
      child: SimSplitApp(),
    ),
  );
}
