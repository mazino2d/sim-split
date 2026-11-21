import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide Group;
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/notifications/announcement.dart';
import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_open.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
import 'package:simsplit/domain/entities/notifications/notification_setup.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/announcements/announcements.dart';
import 'package:simsplit/domain/use_cases/notifications/notification_permission.dart';
import 'package:simsplit/domain/use_cases/notifications/notification_prefs.dart';
import 'package:simsplit/domain/use_cases/telemetry/track_event.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/notification_providers.dart';
import 'package:simsplit/presentation/screens/settings/notifications_screen.dart';
import 'package:simsplit/presentation/widgets/groups/group_app_bar_actions.dart';
import 'package:simsplit/presentation/widgets/notifications/announcement_banner.dart';
import 'package:simsplit/presentation/widgets/notifications/notification_prompt_card.dart';

import '../helpers/mocks.dart';

class _MockTrack extends Mock implements TrackEvent {}

class _MockRequest extends Mock implements RequestNotificationPermission {}

class _MockDismiss extends Mock implements DismissNotificationPrompt {}

class _MockSetCategory extends Mock implements SetNotificationCategory {}

class _MockSetMuted extends Mock implements SetGroupMuted {}

class _MockDismissAnnouncement extends Mock implements DismissAnnouncement {}

NotificationSetup _setup({
  bool supported = true,
  NotificationPermission permission = NotificationPermission.notAsked,
  bool optedIn = false,
  bool promptHandled = false,
}) =>
    NotificationSetup(
      supported: supported,
      permission: permission,
      optedIn: optedIn,
      promptHandled: promptHandled,
    );

void main() {
  late _MockTrack track;
  late _MockRequest request;
  late _MockDismiss dismiss;
  late _MockSetCategory setCategory;
  late _MockSetMuted setMuted;
  late NotificationSetup setup;
  late NotificationPrefs prefs;

  setUpAll(() {
    registerFallbackValue(BreadcrumbKind.op);
    registerFallbackValue(const NoParams());
    registerFallbackValue(const SetNotificationCategoryParams(
        NotificationCategory.updates,
        on: false));
    registerFallbackValue(const SetGroupMutedParams('g', muted: false));
  });

  setUp(() {
    track = _MockTrack();
    request = _MockRequest();
    dismiss = _MockDismiss();
    setCategory = _MockSetCategory();
    setMuted = _MockSetMuted();
    setup = _setup();
    prefs = const NotificationPrefs();
    when(() => request(any())).thenAnswer((_) async {
      setup = _setup(
          permission: NotificationPermission.granted,
          optedIn: true,
          promptHandled: true);
      return right<Failure, NotificationPermissionOutcome>(
          NotificationPermissionOutcome.granted);
    });
    when(() => dismiss(any())).thenAnswer((_) async {
      setup = _setup(promptHandled: true);
      return right<Failure, NotificationPermissionOutcome>(
          NotificationPermissionOutcome.notNow);
    });
    when(() => setCategory(any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
    when(() => setMuted(any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
  });

  Future<void> pump(WidgetTester tester, Widget child, {Group? group}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authAvailableProvider.overrideWithValue(true),
        currentUserProvider
            .overrideWith((ref) => Stream.value(const AuthUser(uid: 'alice'))),
        if (group != null)
          liveGroupProvider('g1').overrideWith((ref) => Stream.value(group)),
        notificationSetupProvider.overrideWith((ref) async => setup),
        notificationPrefsProvider.overrideWith((ref) => Stream.value(prefs)),
        trackEventProvider.overrideWithValue(track),
        requestNotificationPermissionProvider.overrideWithValue(request),
        dismissNotificationPromptProvider.overrideWithValue(dismiss),
        setNotificationCategoryProvider.overrideWithValue(setCategory),
        setGroupMutedProvider.overrideWithValue(setMuted),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ));
    await tester.pumpAndSettle();
  }

  void verifyOp(TelemetryEvent event, String result) =>
      verify(() => track(BreadcrumbKind.op, event.wireName,
          result: result, duration: any(named: 'duration'))).called(1);

  final shared = testGroup().copyWith(memberUids: ['alice', 'bob']);
  const prompt = 'Get a notification when friends add or settle expenses here?';

  group('the one-time card in a group (R-9 AC1)', () {
    Widget card() =>
        const Scaffold(body: NotificationPromptCard(groupId: 'g1'));

    testWidgets('shows in a group with another account', (tester) async {
      await pump(tester, card(), group: shared);
      expect(find.text(prompt), findsOneWidget);
    });

    testWidgets('stays hidden in a group of one, once answered, or when on',
        (tester) async {
      await pump(tester, card(),
          group: testGroup().copyWith(memberUids: ['alice']));
      expect(find.text(prompt), findsNothing);

      setup = _setup(promptHandled: true);
      await pump(tester, card(), group: shared);
      expect(find.text(prompt), findsNothing);

      setup = _setup(permission: NotificationPermission.granted, optedIn: true);
      await pump(tester, card(), group: shared);
      expect(find.text(prompt), findsNothing);

      setup = _setup(supported: false);
      await pump(tester, card(), group: shared);
      expect(find.text(prompt), findsNothing);
    });

    testWidgets('Turn on asks the system and records the outcome',
        (tester) async {
      await pump(tester, card(), group: shared);

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      verify(() => request(any())).called(1);
      verifyOp(TelemetryEvent.opNotificationPermission, 'granted');
      expect(find.text(prompt), findsNothing);
    });

    testWidgets('Not now hides it for good and records not_now',
        (tester) async {
      await pump(tester, card(), group: shared);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      verify(() => dismiss(any())).called(1);
      verifyNever(() => request(any()));
      verifyOp(TelemetryEvent.opNotificationPermission, 'not_now');
      expect(find.text(prompt), findsNothing);
    });
  });

  group('Settings → Notifications (R-9 AC2, AC3)', () {
    testWidgets('one switch per category, with the defaults', (tester) async {
      await pump(tester, const NotificationsScreen());

      expect(find.byType(SwitchListTile), findsNWidgets(3));
      bool on(String title) => tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title))
          .value;
      expect(on('Group activity'), isTrue);
      expect(on('Settle reminders'), isFalse);
      expect(on('Updates'), isFalse);
      expect(
          find.text(
              'A weekly reminder when you still owe money for more than two weeks'),
          findsOneWidget);
    });

    testWidgets('a switch saves the choice and records it', (tester) async {
      await pump(tester, const NotificationsScreen());

      await tester.tap(find.text('Settle reminders'));
      await tester.pumpAndSettle();

      final params = verify(() => setCategory(captureAny())).captured.single
          as SetNotificationCategoryParams;
      expect((params.category, params.on),
          (NotificationCategory.settleReminder, true));
      verifyOp(TelemetryEvent.opSetNotificationPref, 'settle_reminder_on');
    });

    testWidgets('offers Turn on when never asked on this device',
        (tester) async {
      await pump(tester, const NotificationsScreen());
      expect(
          find.text('Notifications are off on this device.'), findsOneWidget);

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      verify(() => request(any())).called(1);
    });

    testWidgets('after a refusal, says where to allow them, without asking',
        (tester) async {
      setup = _setup(
          permission: NotificationPermission.denied,
          optedIn: true,
          promptHandled: true);
      await pump(tester, const NotificationsScreen());

      expect(find.textContaining('Notifications are blocked.'), findsOneWidget);
      expect(find.text('Turn on'), findsNothing);
    });

    testWidgets('says nothing about the device while notifications work',
        (tester) async {
      setup = _setup(
          permission: NotificationPermission.granted,
          optedIn: true,
          promptHandled: true);
      await pump(tester, const NotificationsScreen());

      expect(find.textContaining('Notifications are'), findsNothing);
      expect(find.text('Turn on'), findsNothing);
    });
  });

  group('muting a group (R-9 AC4)', () {
    Widget bar() => Scaffold(
        appBar: AppBar(actions: const [GroupAppBarActions(groupId: 'g1')]));

    testWidgets('Mute notifications mutes the group', (tester) async {
      await pump(tester, bar(), group: shared);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mute notifications'));
      await tester.pumpAndSettle();

      final params = verify(() => setMuted(captureAny())).captured.single
          as SetGroupMutedParams;
      expect((params.groupId, params.muted), ('g1', true));
      verifyOp(TelemetryEvent.opMuteGroup, 'success');
    });

    testWidgets('a muted group offers Unmute', (tester) async {
      prefs = const NotificationPrefs(mutedGroups: ['g1']);
      await pump(tester, bar(), group: shared);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Mute notifications'), findsNothing);
      await tester.tap(find.text('Unmute notifications'));
      await tester.pumpAndSettle();

      final params = verify(() => setMuted(captureAny())).captured.single
          as SetGroupMutedParams;
      expect(params.muted, isFalse);
    });

    testWidgets('is not offered in a group without other accounts',
        (tester) async {
      await pump(tester, bar(),
          group: testGroup().copyWith(memberUids: ['alice']));

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Mute notifications'), findsNothing);
    });
  });

  group('the in-app banner (R-9 AC12)', () {
    late _MockDismissAnnouncement dismissAnnouncement;
    final announcement = Announcement(
      id: '2026-12-01-new-version',
      copy: const {
        'en': AnnouncementCopy(title: 'New version', body: 'It fixes sync.'),
        'vi': AnnouncementCopy(title: 'Bản mới', body: 'Sửa lỗi đồng bộ.'),
      },
      endsAt: DateTime(2100),
    );
    const result = 'campaign_2026_12_01_new_version';

    setUp(() {
      dismissAnnouncement = _MockDismissAnnouncement();
      when(() => dismissAnnouncement(any()))
          .thenAnswer((_) async => right<Failure, Unit>(unit));
    });

    Future<void> pumpBanner(WidgetTester tester, Announcement? shown,
        {Locale locale = const Locale('en')}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authAvailableProvider.overrideWithValue(true),
          currentAnnouncementProvider
              .overrideWith((ref) => Stream.value(shown)),
          trackEventProvider.overrideWithValue(track),
          dismissAnnouncementProvider.overrideWithValue(dismissAnnouncement),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AnnouncementBanner()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the banner in the app language and records it',
        (tester) async {
      await pumpBanner(tester, announcement, locale: const Locale('vi'));

      expect(find.text('Bản mới'), findsOneWidget);
      expect(find.text('Sửa lỗi đồng bộ.'), findsOneWidget);
      verify(() => track(
          BreadcrumbKind.op, TelemetryEvent.opAnnouncementShown.wireName,
          result: result)).called(1);
    });

    testWidgets('shows nothing without an announcement', (tester) async {
      await pumpBanner(tester, null);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('a tap is recorded with the campaign', (tester) async {
      await pumpBanner(tester, announcement);
      await tester.tap(find.text('New version'));
      await tester.pumpAndSettle();
      verify(() => track(
          BreadcrumbKind.tap, TelemetryEvent.tapAnnouncement.wireName,
          result: result)).called(1);
    });

    testWidgets('dismissing hides it and saves it for the account',
        (tester) async {
      await pumpBanner(tester, announcement);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.text('New version'), findsNothing);
      verify(() => dismissAnnouncement('2026-12-01-new-version')).called(1);
      verify(() => track(
          BreadcrumbKind.tap, TelemetryEvent.tapDismissAnnouncement.wireName,
          result: result)).called(1);
      verifyOp(TelemetryEvent.opDismissAnnouncement, 'success');
    });
  });

  test('a tapped notification is recorded by its source, without IDs', () {
    NotificationOpen open({String? source, String? messageId}) =>
        NotificationOpen(
          messageId: messageId,
          category: NotificationCategory.groupActivity,
          route: null,
          source: parseNotificationSource(source),
        );
    expect(open(source: 'trigger:group-activity').usageResult,
        'trigger_group_activity');
    expect(open(source: 'campaign:2026-12-01-new-version').usageResult,
        'campaign_2026_12_01_new_version');
    expect(open(source: 'schedule:settle-reminder').usageResult,
        'schedule_settle_reminder');
    // Older senders, or a source in any other shape: the category.
    for (final source in [
      null,
      'campaign:Bad Id',
      'campaign:x',
      'group:0b6f1c2e',
      'trigger:group-activity:extra',
    ]) {
      expect(open(source: source).usageResult, 'group_activity',
          reason: source);
    }
    expect(
        const NotificationOpen(messageId: null, category: null, route: null)
            .usageResult,
        'unknown');
    final long = open(source: 'campaign:${'a' * 63}').usageResult;
    expect(long, matches(RegExp(r'^[a-z][a-z0-9_]{0,63}$')));
  });
}
