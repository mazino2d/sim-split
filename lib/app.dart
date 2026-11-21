import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/use_cases/telemetry/record_error.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/presentation/providers/locale_provider.dart';
import 'package:simsplit/presentation/providers/notification_providers.dart';
import 'package:simsplit/presentation/providers/sync_providers.dart';
import 'package:simsplit/presentation/providers/theme_mode_provider.dart';
import 'package:simsplit/presentation/router/app_router.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';

class SimSplitApp extends ConsumerStatefulWidget {
  const SimSplitApp({super.key});

  @override
  ConsumerState<SimSplitApp> createState() => _SimSplitAppState();
}

class _SimSplitAppState extends ConsumerState<SimSplitApp> {
  // Usage events are flushed when the app goes to the background, and a new
  // session starts after 30 minutes away (R-4 AC14).
  late final _lifecycle = AppLifecycleListener(
    onHide: () => ref.read(setAppForegroundProvider)(false),
    onShow: () {
      ref.read(setAppForegroundProvider)(true);
      // Notifications may have been allowed in the system settings (R-9 AC2).
      if (ref.read(authAvailableProvider)) {
        ref.invalidate(notificationSetupProvider);
      }
    },
  );

  // Set while a tapped notification's route is being opened (R-9 AC8).
  bool _openingNotification = false;

  /// Opens a tapped notification's route once the user is signed in, after
  /// the router has left the sign-in and starting screens.
  void _openPendingNotification() {
    if (_openingNotification) return;
    final route = ref.read(pendingNotificationRouteProvider);
    if (route == null || !ref.read(authAvailableProvider)) return;
    if (ref.read(currentUserProvider).value == null) return;
    _openingNotification = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openingNotification = false;
      if (!mounted) return;
      ref.read(pendingNotificationRouteProvider.notifier).set(null);
      ref.read(appRouterProvider).go(route);
    });
  }

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localeAsync = ref.watch(localeProvider);
    final locale = localeAsync.value ?? deviceDefaultLocale();
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    ref.watch(syncRunnerProvider);
    // R-9: push registration, Android channels and tapped notifications.
    ref.watch(deviceRegistrationRunnerProvider);
    ref.watch(notificationChannelsProvider);
    ref.watch(notificationOpenRunnerProvider);
    if (ref.watch(authAvailableProvider)) {
      ref.watch(pendingNotificationRouteProvider);
      ref.watch(currentUserProvider);
      _openPendingNotification();
    }
    final recordError = ref.watch(recordErrorProvider);
    onFailureShown = (error) =>
        recordError(RecordErrorParams(error, null, shownToUser: true));

    return MaterialApp.router(
      title: 'SimSplit',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(appRouterProvider),
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('vi', 'VN'),
        Locale('en', 'US'),
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
    );
  }
}
