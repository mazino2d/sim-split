import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
import 'package:simsplit/domain/entities/notifications/notification_setup.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/notification_failure.dart';
import 'package:simsplit/domain/use_cases/notifications/device_registration.dart';
import 'package:simsplit/domain/use_cases/notifications/notification_permission.dart';
import 'package:simsplit/domain/use_cases/notifications/notification_prefs.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

import '../../../helpers/mocks.dart';

NotificationSetup _setup(
        {NotificationPermission permission = NotificationPermission.granted,
        bool optedIn = true}) =>
    NotificationSetup(
      supported: true,
      permission: permission,
      optedIn: optedIn,
      promptHandled: true,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(ActivityEvent.expenseCreate);
    registerFallbackValue(ActivityBundle.tenMinutes);
    registerFallbackValue(const GroupNotifySetting(GroupNotifyMode.off));
    registerFallbackValue(const QuietHours());
    registerFallbackValue(const SettleReminderPrefs());
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(<String>[]);
    registerFallbackValue(<String, GroupNotifySetting>{});
  });

  late MockNotificationRepository devices;
  late MockNotificationPrefsRepository prefs;

  setUp(() {
    devices = MockNotificationRepository();
    prefs = MockNotificationPrefsRepository();
    when(() => devices.registerDevice(any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
    when(() => prefs.setGroup(any(), any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
    when(() => prefs.setPausedUntil(any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
    when(() => prefs.setQuietHours(any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
    when(() => prefs.setSettleReminder(any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
    when(() => prefs.setActivityEvent(any(), any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
    when(() => prefs.setOnlyInvolvingMe(any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
    when(() => prefs.setBundle(any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
    when(() => prefs.migrateMutedGroups(any(), any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
  });

  group('RegisterDevice', () {
    test('registers once the user opted in and the system allows it', () async {
      when(() => devices.setup()).thenAnswer((_) async => _setup());

      await RegisterDevice(repository: devices)('vi');

      verify(() => devices.registerDevice('vi')).called(1);
    });

    test('does nothing before the user turned notifications on (Calm)',
        () async {
      when(() => devices.setup())
          .thenAnswer((_) async => _setup(optedIn: false));

      await RegisterDevice(repository: devices)('en');

      verifyNever(() => devices.registerDevice(any()));
    });

    test('does nothing while the system blocks notifications', () async {
      when(() => devices.setup()).thenAnswer(
          (_) async => _setup(permission: NotificationPermission.denied));

      await RegisterDevice(repository: devices)('en');

      verifyNever(() => devices.registerDevice(any()));
    });

    test('does nothing where push is not offered', () async {
      when(() => devices.setup())
          .thenAnswer((_) async => NotificationSetup.unsupported);

      await RegisterDevice(repository: devices)('en');

      verifyNever(() => devices.registerDevice(any()));
    });
  });

  group('asking for the permission', () {
    test('reports granted and denied as the usage outcome', () async {
      when(() => devices.requestPermission()).thenAnswer((_) async =>
          right<Failure, NotificationPermission>(
              NotificationPermission.granted));
      expect(
          (await RequestNotificationPermission(repository: devices)(
                  const NoParams()))
              .toNullable(),
          NotificationPermissionOutcome.granted);

      when(() => devices.requestPermission()).thenAnswer((_) async =>
          right<Failure, NotificationPermission>(
              NotificationPermission.denied));
      expect(
          (await RequestNotificationPermission(repository: devices)(
                  const NoParams()))
              .toNullable(),
          NotificationPermissionOutcome.denied);
    });

    test('Not now is its own outcome', () async {
      when(() => devices.dismissPrompt())
          .thenAnswer((_) async => right<Failure, Unit>(unit));
      final result = await DismissNotificationPrompt(repository: devices)(
          const NoParams());
      expect(result.toNullable(), NotificationPermissionOutcome.notNow);
      expect(NotificationPermissionOutcome.notNow.wireName, 'not_now');
    });
  });

  group('UpdateNotificationPrefs (AC26–AC32)', () {
    // Saturday 22 November 2026, 21:30 device time.
    final now = DateTime(2026, 11, 22, 21, 30);
    late UpdateNotificationPrefs useCase;

    setUp(() =>
        useCase = UpdateNotificationPrefs(repository: prefs, now: () => now));

    Future<Either<Failure, Unit>> change(NotificationPrefsChange c,
            {NotificationPrefs? current}) =>
        useCase(UpdateNotificationPrefsParams(c, current: current));

    test('saves events, involvement and bundle', () async {
      await change(
          const ActivityEventChange(ActivityEvent.memberJoin, on: true));
      await change(const OnlyInvolvingMeChange(on: true));
      await change(const BundleChange(ActivityBundle.hour));
      verifyInOrder([
        () => prefs.setActivityEvent(ActivityEvent.memberJoin, true),
        () => prefs.setOnlyInvolvingMe(true),
        () => prefs.setBundle(ActivityBundle.hour),
      ]);
    });

    test('a group choice becomes its stored mode (AC29)', () async {
      await change(const GroupChange('g1', GroupNotifyChoice.involving));
      await change(const GroupChange('g1', GroupNotifyChoice.off));
      await change(const GroupChange('g1', GroupNotifyChoice.offUntilMorning));
      await change(const GroupChange('g1', GroupNotifyChoice.all));
      verifyInOrder([
        () => prefs.setGroup(
            'g1', const GroupNotifySetting(GroupNotifyMode.involving)),
        () =>
            prefs.setGroup('g1', const GroupNotifySetting(GroupNotifyMode.off)),
        () => prefs.setGroup(
            'g1',
            GroupNotifySetting(GroupNotifyMode.off,
                offUntil: DateTime(2026, 11, 23, 8))),
        () => prefs.setGroup('g1', null),
      ]);
    });

    test('refuses a new group past the limit the rules allow', () async {
      final full = NotificationPrefs(groups: {
        for (var i = 0; i < maxGroupSettings; i++)
          'g$i': const GroupNotifySetting(GroupNotifyMode.off),
      });
      final refused = await change(
          const GroupChange('new', GroupNotifyChoice.off),
          current: full);
      expect(refused.getLeft().toNullable(),
          isA<NotificationTooManyMutedGroups>());
      verifyNever(() => prefs.setGroup('new', any()));

      // A group already in the map, or All activity, still saves.
      expect(
          (await change(const GroupChange('g3', GroupNotifyChoice.involving),
                  current: full))
              .isRight(),
          isTrue);
      expect(
          (await change(const GroupChange('new', GroupNotifyChoice.all),
                  current: full))
              .isRight(),
          isTrue);
    });

    test('pauses for an hour, until 08:00 or a week; resume clears (AC30)',
        () async {
      await change(const PauseChange(PauseChoice.hour));
      await change(const PauseChange(PauseChoice.untilMorning));
      await change(const PauseChange(PauseChoice.week));
      await change(const PauseChange(null));
      verifyInOrder([
        () => prefs.setPausedUntil(DateTime(2026, 11, 22, 22, 30)),
        () => prefs.setPausedUntil(DateTime(2026, 11, 23, 8)),
        () => prefs.setPausedUntil(DateTime(2026, 11, 29, 21, 30)),
        () => prefs.setPausedUntil(null),
      ]);
    });

    test('refuses quiet hours shorter than 21:00–08:00 (AC31)', () async {
      const longer = QuietHours(from: DayTime(19 * 60), to: DayTime(10 * 60));
      expect((await change(const QuietHoursChange(longer))).isRight(), isTrue);
      verify(() => prefs.setQuietHours(longer)).called(1);

      for (final shorter in const [
        QuietHours(from: DayTime(22 * 60)),
        QuietHours(to: DayTime(7 * 60)),
        QuietHours(from: DayTime(11 * 60)),
        QuietHours(to: DayTime(13 * 60)),
      ]) {
        expect((await change(QuietHoursChange(shorter))).getLeft().toNullable(),
            isA<NotificationInvalidChoice>());
      }
      verifyNever(
          () => prefs.setQuietHours(const QuietHours(from: DayTime(22 * 60))));
    });

    test('settle reminders take a day, a time 08:00–21:00 and 7/14/30 days',
        () async {
      const ok =
          SettleReminderPrefs(day: 6, time: DayTime(8 * 60), minDays: 30);
      expect((await change(const SettleReminderChange(ok))).isRight(), isTrue);
      for (final bad in const [
        SettleReminderPrefs(day: 7),
        SettleReminderPrefs(time: DayTime(7 * 60 + 59)),
        SettleReminderPrefs(time: DayTime(21 * 60 + 1)),
        SettleReminderPrefs(minDays: 10),
      ]) {
        expect((await change(SettleReminderChange(bad))).isLeft(), isTrue);
      }
      verify(() => prefs.setSettleReminder(any())).called(1);
    });

    test('each change has a usage result without IDs', () {
      expect(
          const ActivityEventChange(ActivityEvent.expenseDelete, on: false)
              .usageResult,
          'expense_delete_off');
      expect(const BundleChange(ActivityBundle.tenMinutes).usageResult,
          'bundle_10m');
      expect(
          const GroupChange('secret-id', GroupNotifyChoice.offUntilMorning)
              .usageResult,
          'off_until_morning');
      expect(const PauseChange(null).usageResult, 'resume');
      expect(
          const QuietHoursChange(
                  QuietHours(from: DayTime(20 * 60), to: DayTime(9 * 60)))
              .usageResult,
          'from_2000_to_0900');
      expect(const SettleReminderChange(SettleReminderPrefs()).usageResult,
          'day_0_at_1900_min_14d');
    });
  });

  group('MigrateMutedGroups (AC29)', () {
    test('moves the old list with the current groups', () async {
      const current = NotificationPrefs(
        legacyMutedGroups: ['g1', 'g2'],
        groups: {'g2': GroupNotifySetting(GroupNotifyMode.involving)},
      );
      await MigrateMutedGroups(repository: prefs)(current);
      verify(() => prefs.migrateMutedGroups(['g1', 'g2'], current.groups))
          .called(1);
    });

    test('does nothing without an old list', () async {
      await MigrateMutedGroups(repository: prefs)(const NotificationPrefs());
      verifyNever(() => prefs.migrateMutedGroups(any(), any()));
    });
  });

  test('a test notification is asked of the device repository (AC33)',
      () async {
    when(() => devices.requestTestNotification())
        .thenAnswer((_) async => right<Failure, Unit>(unit));
    await RequestTestNotification(repository: devices)(const NoParams());
    verify(() => devices.requestTestNotification()).called(1);
  });

  test('next morning is the next 08:00 on the device clock', () {
    expect(
        nextMorning(DateTime(2026, 11, 22, 21, 30)), DateTime(2026, 11, 23, 8));
    expect(nextMorning(DateTime(2026, 11, 23, 2)), DateTime(2026, 11, 23, 8));
    expect(nextMorning(DateTime(2026, 11, 23, 8)), DateTime(2026, 11, 24, 8));
    expect(nextMorning(DateTime(2026, 12, 31, 23)), DateTime(2027, 1, 1, 8));
  });

  test('missing choices fall back to the defaults', () {
    const prefs = NotificationPrefs();
    expect(prefs.isOn(NotificationCategory.groupActivity), isTrue);
    expect(prefs.isOn(NotificationCategory.settleReminder), isFalse);
    expect(prefs.isOn(NotificationCategory.updates), isFalse);
    expect(
        const NotificationPrefs(
                categories: {NotificationCategory.groupActivity: false})
            .isOn(NotificationCategory.groupActivity),
        isFalse);
  });
}
