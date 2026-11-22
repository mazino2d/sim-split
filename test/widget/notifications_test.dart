import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:simsplit/presentation/screens/settings/notification_detail_screens.dart';
import 'package:simsplit/presentation/screens/settings/notifications_screen.dart';
import 'package:simsplit/presentation/widgets/groups/group_app_bar_actions.dart';
import 'package:simsplit/presentation/widgets/notifications/announcement_banner.dart';
import 'package:simsplit/presentation/widgets/notifications/notification_prompt_card.dart';

import '../helpers/mocks.dart';

class _MockTrack extends Mock implements TrackEvent {}

class _MockRequest extends Mock implements RequestNotificationPermission {}

class _MockDismiss extends Mock implements DismissNotificationPrompt {}

class _MockSetCategory extends Mock implements SetNotificationCategory {}

class _MockUpdatePrefs extends Mock implements UpdateNotificationPrefs {}

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
  late _MockUpdatePrefs updatePrefs;
  late NotificationSetup setup;
  late NotificationPrefs prefs;

  setUpAll(() {
    registerFallbackValue(BreadcrumbKind.op);
    registerFallbackValue(const NoParams());
    registerFallbackValue(const SetNotificationCategoryParams(
        NotificationCategory.updates,
        on: false));
    registerFallbackValue(
        const UpdateNotificationPrefsParams(OnlyInvolvingMeChange(on: false)));
  });

  setUp(() {
    track = _MockTrack();
    request = _MockRequest();
    dismiss = _MockDismiss();
    setCategory = _MockSetCategory();
    updatePrefs = _MockUpdatePrefs();
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
    when(() => updatePrefs(any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
  });

  // Saturday 22 November 2026, 21:30 device time.
  final now = DateTime(2026, 11, 22, 21, 30);

  Future<void> pump(WidgetTester tester, Widget child,
      {Group? group, GoRouter? router}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationClockProvider.overrideWithValue(() => now),
        groupListProvider
            .overrideWith((ref) => Stream.value([if (group != null) group])),
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
        updateNotificationPrefsProvider.overrideWithValue(updatePrefs),
      ],
      child: router != null
          ? MaterialApp.router(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            )
          : MaterialApp(
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

  NotificationPrefsChange savedChange() =>
      (verify(() => updatePrefs(captureAny())).captured.single
              as UpdateNotificationPrefsParams)
          .change;

  group('Settings → Notifications (R-9 AC2, AC3, AC26–AC32)', () {
    bool switchOn(WidgetTester tester, int index) =>
        tester.widgetList<Switch>(find.byType(Switch)).elementAt(index).value;

    testWidgets('one switch per category, with the defaults and subtitles',
        (tester) async {
      await pump(tester, const NotificationsScreen());

      expect(find.byType(Switch), findsNWidgets(3));
      expect(switchOn(tester, 0), isTrue);
      expect(switchOn(tester, 1), isFalse);
      expect(switchOn(tester, 2), isFalse);
      expect(find.text('Every 10 min · all changes'), findsOneWidget);
      expect(find.text('Off · weekly while you still owe'), findsOneWidget);
      expect(find.text('Off · rare news about SimSplit'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget); // Pause
      expect(find.text('21:00 – 08:00 · no notifications'), findsOneWidget);
      expect(find.text('All groups: all activity'), findsOneWidget);
    });

    testWidgets('subtitles follow the choices', (tester) async {
      prefs = NotificationPrefs(
        categories: const {NotificationCategory.settleReminder: true},
        onlyInvolvingMe: true,
        bundle: ActivityBundle.daily,
        settle: const SettleReminderPrefs(
            day: 5, time: DayTime(20 * 60 + 30), minDays: 30),
        quietHours:
            const QuietHours(from: DayTime(20 * 60), to: DayTime(9 * 60)),
        groups: {
          'g1': const GroupNotifySetting(GroupNotifyMode.off),
          'g2': GroupNotifySetting(GroupNotifyMode.off,
              offUntil: DateTime(2026, 11, 22, 8)), // already over
        },
      );
      await pump(tester, const NotificationsScreen());

      expect(find.text('Summary at 19:00 · only involving me'), findsOneWidget);
      expect(find.text('Friday, 20:30 · debts over 30 days'), findsOneWidget);
      expect(find.text('20:00 – 09:00 · no notifications'), findsOneWidget);
      expect(find.text('1 group changed'), findsOneWidget);
    });

    testWidgets('a switch saves the choice and records it', (tester) async {
      await pump(tester, const NotificationsScreen());

      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();

      final params = verify(() => setCategory(captureAny())).captured.single
          as SetNotificationCategoryParams;
      expect((params.category, params.on),
          (NotificationCategory.settleReminder, true));
      verifyOp(TelemetryEvent.opSetNotificationPref, 'settle_reminder_on');
    });

    testWidgets('Updates has no detail: tapping its row toggles it',
        (tester) async {
      await pump(tester, const NotificationsScreen());

      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();

      final params = verify(() => setCategory(captureAny())).captured.single
          as SetNotificationCategoryParams;
      expect(
          (params.category, params.on), (NotificationCategory.updates, true));
    });

    testWidgets('while paused, shows the end and Resume (AC30)',
        (tester) async {
      prefs = NotificationPrefs(pausedUntil: DateTime(2026, 11, 23, 8));
      await pump(tester, const NotificationsScreen());

      expect(find.text('Paused until 08:00 tomorrow'), findsOneWidget);
      expect(find.text('Until 08:00 tomorrow'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      expect((savedChange() as PauseChange).choice, isNull);
      verifyOp(TelemetryEvent.opPauseNotifications, 'resume');
    });

    testWidgets('a pause that ended shows as off', (tester) async {
      prefs = NotificationPrefs(pausedUntil: DateTime(2026, 11, 22, 21));
      await pump(tester, const NotificationsScreen());
      expect(find.text('Resume'), findsNothing);
    });

    testWidgets('offers Turn on when never asked on this device',
        (tester) async {
      await pump(tester, const NotificationsScreen());
      expect(
          find.text('Notifications are off on this device.'), findsOneWidget);

      await tester.ensureVisible(find.text('Turn on'));
      await tester.pumpAndSettle();
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

    testWidgets('says the device gets them while notifications work',
        (tester) async {
      setup = _setup(
          permission: NotificationPermission.granted,
          optedIn: true,
          promptHandled: true);
      await pump(tester, const NotificationsScreen());

      expect(find.text('This device gets notifications.'), findsOneWidget);
      expect(find.text('Turn on'), findsNothing);
    });
  });

  group('Group activity (R-9 AC26–AC28)', () {
    testWidgets('one switch per event with the defaults', (tester) async {
      await pump(tester, const GroupActivitySettingsScreen());

      bool on(String title) => tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title))
          .value;
      expect(on('New expenses'), isTrue);
      expect(on('Edited expenses'), isTrue);
      expect(on('Deleted expenses'), isTrue);
      expect(on('Settlements'), isTrue);
      expect(on('Members joining'), isFalse);
      expect(on('Only changes that involve me'), isFalse);
      final radio = tester.widget<RadioGroup<ActivityBundle>>(
          find.byType(RadioGroup<ActivityBundle>));
      expect(radio.groupValue, ActivityBundle.tenMinutes);
    });

    testWidgets('an event switch saves and records it', (tester) async {
      await pump(tester, const GroupActivitySettingsScreen());

      await tester.tap(find.text('Members joining'));
      await tester.pumpAndSettle();

      final change = savedChange() as ActivityEventChange;
      expect((change.event, change.on), (ActivityEvent.memberJoin, true));
      verifyOp(TelemetryEvent.opSetActivityEvent, 'member_join_on');
    });

    testWidgets('only involving me saves and records it', (tester) async {
      await pump(tester, const GroupActivitySettingsScreen());

      await tester.tap(find.text('Only changes that involve me'));
      await tester.pumpAndSettle();

      expect((savedChange() as OnlyInvolvingMeChange).on, isTrue);
      verifyOp(TelemetryEvent.opSetOnlyInvolvingMe, 'on');
    });

    testWidgets('a bundle saves and records it', (tester) async {
      await pump(tester, const GroupActivitySettingsScreen());

      await tester.ensureVisible(find.text('Every hour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Every hour'));
      await tester.pumpAndSettle();

      expect((savedChange() as BundleChange).bundle, ActivityBundle.hour);
      verifyOp(TelemetryEvent.opSetNotificationBundle, 'bundle_1h');
    });
  });

  group('Settle reminders (R-9 AC32)', () {
    testWidgets('day, time and debt age each save the whole choice',
        (tester) async {
      await pump(tester, const SettleReminderSettingsScreen());

      await tester.tap(find.text('Fri'));
      await tester.pumpAndSettle();
      expect((savedChange() as SettleReminderChange).settle,
          const SettleReminderPrefs(day: 5));
      verifyOp(TelemetryEvent.opSetSettleReminder, 'day_5_at_1900_min_14d');

      await tester.tap(find.text('20:30'));
      await tester.pumpAndSettle();
      expect((savedChange() as SettleReminderChange).settle.time.hhmm, '20:30');

      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();
      expect((savedChange() as SettleReminderChange).settle.minDays, 30);
      expect(find.text('14 days (default)'), findsOneWidget);
    });
  });

  group('Pause and quiet hours (R-9 AC30, AC31)', () {
    testWidgets('a pause length saves and records it', (tester) async {
      await pump(tester, const NotificationPauseScreen());

      await tester.tap(find.text('Until 08:00 tomorrow'));
      await tester.pumpAndSettle();

      expect((savedChange() as PauseChange).choice, PauseChoice.untilMorning);
      verifyOp(TelemetryEvent.opPauseNotifications, 'until_morning');
    });

    testWidgets('quiet hours offer only longer ranges', (tester) async {
      await pump(tester, const QuietHoursScreen());

      for (final shorter in ['22:00', '07:00', '23:00']) {
        expect(find.text(shorter), findsNothing);
      }
      await tester.tap(find.text('20:00'));
      await tester.pumpAndSettle();

      final quiet = (savedChange() as QuietHoursChange).quietHours;
      expect((quiet.from.hhmm, quiet.to.hhmm), ('20:00', '08:00'));
      verifyOp(TelemetryEvent.opSetQuietHours, 'from_2000_to_0800');
    });
  });

  group("a group's notifications (R-9 AC29)", () {
    GoRouter router() => GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
                appBar:
                    AppBar(actions: const [GroupAppBarActions(groupId: 'g1')])),
          ),
          GoRoute(
            path: '/settings/notifications/groups',
            builder: (_, __) => const GroupNotificationsListScreen(),
          ),
          GoRoute(
            path: '/groups/:groupId/notifications',
            builder: (_, state) => GroupNotificationsScreen(
                groupId: state.pathParameters['groupId']!),
          ),
        ]);

    testWidgets('the group menu opens the four choices; Off saves it',
        (tester) async {
      await pump(tester, const SizedBox(), group: shared, router: router());

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      for (final choice in [
        'All activity',
        'Only changes that involve me',
        'Off until 08:00 tomorrow',
        'Off',
      ]) {
        expect(find.text(choice), findsOneWidget);
      }
      verify(() => track(BreadcrumbKind.tap,
          TelemetryEvent.tapMenuGroupNotifications.wireName)).called(1);

      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();

      final change = savedChange() as GroupChange;
      expect((change.groupId, change.choice), ('g1', GroupNotifyChoice.off));
      verifyOp(TelemetryEvent.opSetGroupNotifications, 'off');
    });

    testWidgets('a group muted before v2 shows as Off', (tester) async {
      prefs = const NotificationPrefs(legacyMutedGroups: ['g1']);
      await pump(tester, const SizedBox(), group: shared, router: router());
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      final radio = tester.widget<RadioGroup<GroupNotifyChoice>>(
          find.byType(RadioGroup<GroupNotifyChoice>));
      expect(radio.groupValue, GroupNotifyChoice.off);
    });

    testWidgets('is not offered in a group without other accounts',
        (tester) async {
      await pump(tester, const SizedBox(),
          group: testGroup().copyWith(memberUids: ['alice']), router: router());

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsNothing);
    });

    testWidgets('By group lists shared groups with a bell-off when off',
        (tester) async {
      prefs = NotificationPrefs(groups: {
        'g1': GroupNotifySetting(GroupNotifyMode.off,
            offUntil: DateTime(2026, 11, 23, 8)),
      });
      final r = router()..go('/settings/notifications/groups');
      await pump(tester, const SizedBox(), group: shared, router: r);

      expect(find.text('Group g1'), findsOneWidget);
      expect(find.text('Off until 08:00 tomorrow'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

      await tester.tap(find.text('Group g1'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications from this group'), findsOneWidget);
    });

    testWidgets('only involving me shows no bell-off', (tester) async {
      prefs = const NotificationPrefs(groups: {
        'g1': GroupNotifySetting(GroupNotifyMode.involving),
      });
      final r = router()..go('/settings/notifications/groups');
      await pump(tester, const SizedBox(), group: shared, router: r);

      expect(find.text('Only changes that involve me'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
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
