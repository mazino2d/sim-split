import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/presentation/providers/locale_provider.dart';
import 'package:simsplit/presentation/providers/sync_providers.dart';
import 'package:simsplit/presentation/providers/theme_mode_provider.dart';
import 'package:simsplit/presentation/router/app_router.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';

class SimSplitApp extends ConsumerWidget {
  const SimSplitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeAsync = ref.watch(localeProvider);
    final locale = localeAsync.value ?? deviceDefaultLocale();
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    ref.watch(syncRunnerProvider);

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
