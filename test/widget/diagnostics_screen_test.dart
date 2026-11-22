import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/notifications/notification_setup.dart';
import 'package:simsplit/domain/entities/telemetry/error_report_settings.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/telemetry_repository.dart';
import 'package:simsplit/domain/use_cases/notifications/device_registration.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/presentation/providers/notification_providers.dart';
import 'package:simsplit/presentation/router/app_routes.dart';
import 'package:simsplit/presentation/screens/settings/diagnostics_screen.dart';
import 'package:simsplit/presentation/screens/settings/settings_screen.dart';

class _MockRequestTest extends Mock implements RequestTestNotification {}

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

  final tracked = <String>[];

  @override
  void track(BreadcrumbKind kind, String name,
          {String? result, Duration? duration}) =>
      tracked.add(name);

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

  Future<void> pump(WidgetTester tester, String initial,
      {NotificationSetup? push, RequestTestNotification? testRequest}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authAvailableProvider.overrideWithValue(false),
        telemetryRepositoryProvider.overrideWithValue(telemetry),
        if (push != null)
          notificationSetupProvider.overrideWith((ref) async => push),
        if (testRequest != null)
          requestTestNotificationProvider.overrideWithValue(testRequest),
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

  testWidgets('tapping the app version copies it and confirms (#127)',
      (tester) async {
    await pump(tester, AppRoutes.diagnostics);
    await tester.tap(find.text('App version'));
    await tester.pumpAndSettle();
    expect(copied, ['2026.10.22+7']);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('Copy all copies every detail in one block (#127)',
      (tester) async {
    await pump(tester, AppRoutes.diagnostics);
    await tester.tap(find.byTooltip('Copy all'));
    await tester.pumpAndSettle();
    expect(copied, [
      'App version: 2026.10.22+7\n'
          'Platform: android\n'
          'Report ID: 7KQ-4MZ\n'
          'Reports waiting: 2',
    ]);
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

  group('Send a test notification (R-9 AC33)', () {
    const active = NotificationSetup(
      supported: true,
      permission: NotificationPermission.granted,
      optedIn: true,
      promptHandled: true,
    );

    testWidgets('asks for one push to this device and confirms',
        (tester) async {
      final request = _MockRequestTest();
      when(() => request(const NoParams()))
          .thenAnswer((_) async => right<Failure, Unit>(unit));
      await pump(tester, AppRoutes.diagnostics,
          push: active, testRequest: request);

      await tester.ensureVisible(find.text('Send a test notification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send a test notification'));
      await tester.pumpAndSettle();

      verify(() => request(const NoParams())).called(1);
      expect(
          find.text(
              'Test notification sent to this device. Try again in 10 minutes.'),
          findsOneWidget);
      expect(telemetry.tracked, contains('tap_send_test_notification'));
      expect(telemetry.tracked, contains('op_request_test_notification'));
    });

    testWidgets('is disabled until this device gets notifications',
        (tester) async {
      await pump(tester, AppRoutes.diagnostics,
          push: const NotificationSetup(
            supported: true,
            permission: NotificationPermission.notAsked,
            optedIn: false,
            promptHandled: false,
          ));
      await tester.ensureVisible(find.text('Send a test notification'));
      expect(
          tester
              .widget<ListTile>(
                  find.widgetWithText(ListTile, 'Send a test notification'))
              .enabled,
          isFalse);
    });

    testWidgets('is hidden where push is not offered', (tester) async {
      await pump(tester, AppRoutes.diagnostics);
      expect(find.text('Send a test notification'), findsNothing);
    });
  });
}
