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
  late MockNotificationRepository devices;
  late MockNotificationPrefsRepository prefs;

  setUp(() {
    devices = MockNotificationRepository();
    prefs = MockNotificationPrefsRepository();
    when(() => devices.registerDevice(any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
    when(() => prefs.setGroupMuted(any(), any()))
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

  group('SetGroupMuted', () {
    final full = NotificationPrefs(
        mutedGroups: [for (var i = 0; i < maxMutedGroups; i++) 'g$i']);

    test('mutes and unmutes a group (AC4)', () async {
      final useCase = SetGroupMuted(repository: prefs);
      await useCase(const SetGroupMutedParams('g1', muted: true));
      await useCase(const SetGroupMutedParams('g1', muted: false));
      verifyInOrder([
        () => prefs.setGroupMuted('g1', true),
        () => prefs.setGroupMuted('g1', false),
      ]);
    });

    test('refuses a mute past the limit the rules allow', () async {
      final result = await SetGroupMuted(repository: prefs)(
          SetGroupMutedParams('new', muted: true, current: full));
      expect(
          result.getLeft().toNullable(), isA<NotificationTooManyMutedGroups>());
      verifyNever(() => prefs.setGroupMuted(any(), any()));
    });

    test('still unmutes, or mutes an already muted group, at the limit',
        () async {
      final useCase = SetGroupMuted(repository: prefs);
      expect(
          (await useCase(
                  SetGroupMutedParams('g3', muted: false, current: full)))
              .isRight(),
          isTrue);
      expect(
          (await useCase(SetGroupMutedParams('g3', muted: true, current: full)))
              .isRight(),
          isTrue);
    });
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
