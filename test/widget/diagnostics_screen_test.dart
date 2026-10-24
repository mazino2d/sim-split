import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/telemetry/error_report_settings.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/telemetry_repository.dart';
import 'package:simsplit/presentation/router/app_routes.dart';
import 'package:simsplit/presentation/screens/settings/diagnostics_screen.dart';
import 'package:simsplit/presentation/screens/settings/settings_screen.dart';

class _FakeTelemetry implements TelemetryRepository {
  final _controller = StreamController<ErrorReportSettings>.broadcast();
  ErrorReportSettings current = const ErrorReportSettings(
    enabled: true,
    reportId: '7KQ-4MZ',
    waitingCount: 2,
    appVersion: '2026.10.22+7',
    platform: 'android',
  );

  @override
  Stream<Either<Failure, ErrorReportSettings>>
      watchErrorReportSettings() async* {
    yield right(current);
    yield* _controller.stream.map(right);
  }

  @override
  Future<Either<Failure, Unit>> setErrorReportsEnabled(bool enabled) async {
    current = ErrorReportSettings(
      enabled: enabled,
      reportId: enabled ? 'NEW-ID2' : null,
      waitingCount: 0,
      appVersion: current.appVersion,
      platform: current.platform,
    );
    _controller.add(current);
    return right(unit);
  }

  @override
  void track(BreadcrumbKind kind, String name,
      {String? result, Duration? duration}) {}

  @override
  void setForeground(bool foreground) {}

  @override
  void recordError(Object error, StackTrace? stack,
      {required bool shownToUser}) {}
}

void main() {
  late _FakeTelemetry telemetry;
  final copied = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    telemetry = _FakeTelemetry();
    copied.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  Future<void> pump(WidgetTester tester, String initial) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authAvailableProvider.overrideWithValue(false),
        telemetryRepositoryProvider.overrideWithValue(telemetry),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(initialLocation: initial, routes: [
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'diagnostics',
                builder: (_, __) => const DiagnosticsScreen(),
              ),
            ],
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Settings shows no error report details, only the wrench (AC25)',
      (tester) async {
    await pump(tester, '/settings');
    expect(find.text('Send anonymous error reports'), findsNothing);
    expect(find.text('7KQ-4MZ'), findsNothing);
    await tester.tap(find.byTooltip('Diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('Send anonymous error reports'), findsOneWidget);
  });

  testWidgets('Diagnostics shows the switch, report ID and debug details',
      (tester) async {
    await pump(tester, AppRoutes.diagnostics);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('7KQ-4MZ'), findsOneWidget);
    expect(find.text('2026.10.22+7'), findsOneWidget);
    expect(find.text('android'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('tapping the report ID copies it and confirms (AC27)',
      (tester) async {
    await pump(tester, AppRoutes.diagnostics);
    await tester.tap(find.text('Report ID'));
    await tester.pumpAndSettle();
    expect(copied, ['7KQ-4MZ']);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('turning the switch off hides the report ID (AC26)',
      (tester) async {
    await pump(tester, AppRoutes.diagnostics);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('7KQ-4MZ'), findsNothing);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse);
  });
}
