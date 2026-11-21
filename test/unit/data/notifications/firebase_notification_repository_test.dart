import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsplit/data/notifications/firebase_notification_repository.dart';
import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_setup.dart';
import 'package:simsplit/domain/repositories/notification_repository.dart';

class _MockMessaging extends Mock implements FirebaseMessaging {}

NotificationSettings _settings(AuthorizationStatus status) =>
    NotificationSettings(
      alert: AppleNotificationSetting.notSupported,
      announcement: AppleNotificationSetting.notSupported,
      authorizationStatus: status,
      badge: AppleNotificationSetting.notSupported,
      carPlay: AppleNotificationSetting.notSupported,
      lockScreen: AppleNotificationSetting.notSupported,
      notificationCenter: AppleNotificationSetting.notSupported,
      showPreviews: AppleShowPreviewSetting.notSupported,
      timeSensitive: AppleNotificationSetting.notSupported,
      criticalAlert: AppleNotificationSetting.notSupported,
      sound: AppleNotificationSetting.notSupported,
      providesAppNotificationSettings: AppleNotificationSetting.notSupported,
    );

void main() {
  late _MockMessaging messaging;
  late FakeFirebaseFirestore firestore;
  late StreamController<RemoteMessage> opened;
  late List<List<Map<String, String>>> channels;
  String? uid;
  var version = '2026.11.21+8';
  var ids = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messaging = _MockMessaging();
    firestore = FakeFirebaseFirestore();
    opened = StreamController<RemoteMessage>.broadcast();
    channels = [];
    uid = 'alice';
    version = '2026.11.21+8';
    ids = 0;
    // ignore: deprecated_member_use
    when(() => messaging.getToken(vapidKey: any(named: 'vapidKey')))
        .thenAnswer((_) async => 'token-1');
    // ignore: deprecated_member_use
    when(() => messaging.deleteToken()).thenAnswer((_) async {});
    when(() => messaging.getNotificationSettings())
        .thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
  });

  tearDown(() => opened.close());

  FirebaseNotificationRepository repo({String? platform = 'android'}) =>
      FirebaseNotificationRepository(
        messaging: () => messaging,
        firestore: firestore,
        currentUid: () => uid,
        platform: platform,
        openedMessages: () => opened.stream,
        appVersion: () async => version,
        timeZoneName: () async => 'Asia/Ho_Chi_Minh',
        createChannels: (c) async => channels.add(c),
        newId: () => 'device-${++ids}',
        now: () => DateTime.utc(2026, 11, 21),
      );

  Future<List<Map<String, dynamic>>> devices(String uid) async => [
        for (final d
            in (await firestore.collection('users/$uid/devices').get()).docs)
          {'id': d.id, ...d.data()},
      ];

  group('registering this device', () {
    test('stores the token, language, time zone and version under the account',
        () async {
      final result = await repo().registerDevice('vi');

      expect(result.isRight(), isTrue);
      final stored = await devices('alice');
      expect(stored, hasLength(1));
      expect(stored.single['id'], 'device-1');
      expect(stored.single['token'], 'token-1');
      expect(stored.single['platform'], 'android');
      expect(stored.single['locale'], 'vi');
      expect(stored.single['tzName'], 'Asia/Ho_Chi_Minh');
      expect(stored.single['tzOffsetMinutes'], isA<int>());
      expect(stored.single['appVersion'], '2026.11.21+8');
      expect(stored.single.containsKey('updatedAt'), isTrue);
      expect(stored.single.keys.toSet(), {
        'id',
        'token',
        'platform',
        'locale',
        'tzName',
        'tzOffsetMinutes',
        'appVersion',
        'updatedAt',
      });
    });

    test('keeps one device ID per install, across accounts', () async {
      await repo().registerDevice('en');
      uid = 'bob';
      await repo().registerDevice('en');

      expect((await devices('alice')).single['id'], 'device-1');
      expect((await devices('bob')).single['id'], 'device-1');
    });

    test('writes again only when something changed', () async {
      await repo().registerDevice('en');
      await firestore.doc('users/alice/devices/device-1').update({'mark': 1});

      await repo().registerDevice('en');
      expect((await devices('alice')).single['mark'], 1);

      version = '2026.12.1+9';
      await repo().registerDevice('en');
      final stored = (await devices('alice')).single;
      expect(stored.containsKey('mark'), isFalse);
      expect(stored['appVersion'], '2026.12.1+9');
    });

    test('does nothing while signed out or where push is not offered',
        () async {
      uid = null;
      expect((await repo().registerDevice('en')).isRight(), isTrue);
      uid = 'alice';
      expect(
          (await repo(platform: null).registerDevice('en')).isRight(), isTrue);
      expect(await devices('alice'), isEmpty);
    });
  });

  test('sign-out removes this device and its token (AC23)', () async {
    await repo().registerDevice('en');
    await firestore.doc('users/alice/devices/other').set({'token': 't2'});

    final result = await repo().unregisterDevice();

    expect(result.isRight(), isTrue);
    expect((await devices('alice')).map((d) => d['id']), ['other']);
    // ignore: deprecated_member_use
    verify(() => messaging.deleteToken()).called(1);
    // Signing in again registers afresh.
    await repo().registerDevice('en');
    expect(await devices('alice'), hasLength(2));
  });

  test('account deletion removes every device of the account (AC23)', () async {
    await repo().registerDevice('en');
    await firestore.doc('users/alice/devices/other').set({'token': 't2'});
    await firestore.doc('users/bob/devices/x').set({'token': 't3'});

    final result = await repo().deleteAllDevices();

    expect(result.isRight(), isTrue);
    expect(await devices('alice'), isEmpty);
    expect(await devices('bob'), hasLength(1));
  });

  group('permission', () {
    test('maps the system status and remembers the user opted in', () async {
      expect((await repo().setup()).optedIn, isFalse);
      when(() => messaging.requestPermission()).thenAnswer(
          (_) async => _settings(AuthorizationStatus.deniedPermanently));

      final result = await repo().requestPermission();

      expect(result.toNullable(), NotificationPermission.denied);
      final setup = await repo().setup();
      expect(setup.optedIn, isTrue);
      expect(setup.promptHandled, isTrue);
    });

    test('Not now hides the card without opting in', () async {
      await repo().dismissPrompt();
      final setup = await repo().setup();
      expect(setup.promptHandled, isTrue);
      expect(setup.optedIn, isFalse);
    });

    test('a web permission never asked is not a refusal', () async {
      when(() => messaging.getNotificationSettings()).thenAnswer(
          (_) async => _settings(AuthorizationStatus.notDetermined));
      expect((await repo(platform: 'web').setup()).permission,
          NotificationPermission.notAsked);
    });

    test('is unsupported without a push platform', () async {
      expect((await repo(platform: null).setup()).supported, isFalse);
    });
  });

  test('a tapped notification opens only a valid route (AC8)', () async {
    const g = '0b6f1c2e-4a5d-4e8f-9a1b-2c3d4e5f6a7b';
    final opens = repo().opens().take(2).toList();
    opened.add(const RemoteMessage(data: {
      'messageId': 'm1',
      'category': 'group_activity',
      'route': '/groups/$g',
    }));
    opened.add(const RemoteMessage(data: {
      'category': 'nope',
      'route': 'https://evil.example',
    }));

    final [first, second] = await opens;
    expect(first.messageId, 'm1');
    expect(first.category, NotificationCategory.groupActivity);
    expect(first.route, '/groups/$g');
    expect(second.category, isNull);
    expect(second.route, isNull);
  });

  test('creates one Android channel per category, only on Android (AC5)',
      () async {
    final specs = [
      for (final c in NotificationCategory.values)
        NotificationChannelSpec(category: c, name: c.id, description: 'd'),
    ];
    await repo(platform: 'web').setUpChannels(specs);
    expect(channels, isEmpty);

    await repo().setUpChannels(specs);
    expect(channels.single.map((c) => c['id']),
        ['group_activity', 'settle_reminder', 'updates']);
  });
}
