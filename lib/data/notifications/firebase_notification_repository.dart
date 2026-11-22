import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_open.dart';
import 'package:simsplit/domain/entities/notifications/notification_setup.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/notification_failure.dart';
import 'package:simsplit/domain/repositories/notification_repository.dart';

/// Push through Firebase Cloud Messaging (R-9 P2).
///
/// It stores the FCM registration token, which the sender targets with the
/// Admin SDK. firebase_messaging 17 deprecates the token API in favour of
/// Firebase Installation ID registration (`register()`, `onRegistered`); the
/// token API still works, and moving to FIDs would change the device data
/// model the sender reads, so that waits for a change on both sides. This device is
/// `users/{uid}/devices/{deviceId}`, where `deviceId` is a random ID made
/// once per install. It is not the R-4 error-report ID, which stays
/// unlinked from the account.
class FirebaseNotificationRepository implements NotificationRepository {
  FirebaseNotificationRepository({
    required FirebaseMessaging Function() messaging,
    required FirebaseFirestore firestore,
    required String? Function() currentUid,
    required this.platform,
    required Stream<RemoteMessage> Function() openedMessages,
    required Future<String> Function() appVersion,
    required Future<String> Function() timeZoneName,
    required Future<void> Function(List<Map<String, String>>) createChannels,
    required String Function() newId,
    String? vapidKey,
    DateTime Function()? now,
    void Function(String)? log,
  })  : _messaging = messaging,
        _firestore = firestore,
        _currentUid = currentUid,
        _openedMessages = openedMessages,
        _appVersion = appVersion,
        _timeZoneName = timeZoneName,
        _createChannels = createChannels,
        _newId = newId,
        _vapidKey = vapidKey,
        _now = now ?? DateTime.now,
        _log = log ?? ((_) {});

  /// `android` or `web`; null where push is not offered (iOS until R-3 P8,
  /// desktop, or a web build without a Web Push key).
  final String? platform;

  final FirebaseMessaging Function() _messaging;
  final FirebaseFirestore _firestore;
  final String? Function() _currentUid;
  final Stream<RemoteMessage> Function() _openedMessages;
  final Future<String> Function() _appVersion;
  final Future<String> Function() _timeZoneName;
  final Future<void> Function(List<Map<String, String>>) _createChannels;
  final String Function() _newId;
  final String? _vapidKey;
  final DateTime Function() _now;
  final void Function(String) _log;

  static const deviceIdKey = 'push_device_id';
  static const optedInKey = 'push_opted_in';
  static const promptHandledKey = 'push_prompt_handled';
  static String registeredKey(String uid) => 'push_device_registered:$uid';

  static const _writeTimeout = Duration(seconds: 10);

  bool get _supported => platform != null;

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(deviceIdKey);
    if (existing != null) return existing;
    final id = _newId();
    await prefs.setString(deviceIdKey, id);
    return id;
  }

  DocumentReference<Map<String, dynamic>> _device(String uid, String id) =>
      _firestore.collection('users').doc(uid).collection('devices').doc(id);

  NotificationPermission _permission(NotificationSettings settings) =>
      switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional =>
          NotificationPermission.granted,
        AuthorizationStatus.notDetermined => NotificationPermission.notAsked,
        AuthorizationStatus.denied ||
        AuthorizationStatus.deniedPermanently =>
          NotificationPermission.denied,
      };

  @override
  Future<NotificationSetup> setup() async {
    if (!_supported) return NotificationSetup.unsupported;
    final prefs = await SharedPreferences.getInstance();
    NotificationPermission permission;
    try {
      permission = _permission(await _messaging().getNotificationSettings());
    } on Object catch (e) {
      _log('permission check failed: $e');
      permission = NotificationPermission.denied;
    }
    return NotificationSetup(
      supported: true,
      permission: permission,
      optedIn: prefs.getBool(optedInKey) ?? false,
      promptHandled: prefs.getBool(promptHandledKey) ?? false,
    );
  }

  @override
  Future<Either<Failure, NotificationPermission>> requestPermission() async {
    if (!_supported) return right(NotificationPermission.denied);
    final prefs = await SharedPreferences.getInstance();
    // Whatever the answer, the card never shows again on this install.
    await prefs.setBool(optedInKey, true);
    await prefs.setBool(promptHandledKey, true);
    try {
      return right(_permission(await _messaging().requestPermission()));
    } on Object catch (e) {
      return left(Failure.unexpected('permission request failed: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> dismissPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(promptHandledKey, true);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> registerDevice(String locale) async {
    final uid = _currentUid();
    if (!_supported || uid == null) return right(unit);
    try {
      // ignore: deprecated_member_use
      final token = await _messaging().getToken(vapidKey: _vapidKey);
      if (token == null || token.isEmpty) {
        _log('no push token');
        return right(unit);
      }
      final tzName = await _safeTimeZoneName();
      final fields = <String, Object>{
        'token': token,
        'platform': platform!,
        'locale': locale == 'vi' ? 'vi' : 'en',
        'tzName': tzName,
        'tzOffsetMinutes':
            _now().timeZoneOffset.inMinutes.clamp(-720, 840).toInt(),
        'appVersion': _truncate(await _appVersion(), 40),
      };
      final prefs = await SharedPreferences.getInstance();
      final fingerprint = jsonEncode(fields);
      if (prefs.getString(registeredKey(uid)) == fingerprint) {
        return right(unit);
      }
      final id = await _deviceId();
      await _device(uid, id)
          .set({...fields, 'updatedAt': FieldValue.serverTimestamp()}).timeout(
              _writeTimeout);
      await prefs.setString(registeredKey(uid), fingerprint);
      return right(unit);
    } on Object catch (e) {
      _log('device registration failed: $e');
      return left(Failure.unexpected('device registration failed: $e'));
    }
  }

  Future<String> _safeTimeZoneName() async {
    try {
      final name = await _timeZoneName();
      if (name.isNotEmpty && name.length <= 64) return name;
    } on Object catch (e) {
      _log('time zone unavailable: $e');
    }
    return 'Etc/UTC';
  }

  static String _truncate(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  @override
  Stream<Unit> tokenRefreshes() => _supported
      // ignore: deprecated_member_use
      ? _messaging().onTokenRefresh.map((_) => unit)
      : const Stream.empty();

  @override
  Future<Either<Failure, Unit>> requestTestNotification() async {
    final uid = _currentUid();
    if (!_supported || uid == null) {
      return left(const NotificationFailure.deviceNotRegistered());
    }
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(deviceIdKey);
    if (id == null || prefs.getString(registeredKey(uid)) == null) {
      return left(const NotificationFailure.deviceNotRegistered());
    }
    try {
      // Only this field changes; the rules check it is the server time.
      await _device(uid, id)
          .update({'testRequestedAt': FieldValue.serverTimestamp()}).timeout(
              _writeTimeout);
      return right(unit);
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        await prefs.remove(registeredKey(uid));
        return left(const NotificationFailure.deviceNotRegistered());
      }
      return left(Failure.unexpected('${e.code} ${e.message}'));
    } on TimeoutException {
      return left(const Failure.unexpected('test request timed out'));
    }
  }

  @override
  Future<Either<Failure, Unit>> unregisterDevice() async {
    final uid = _currentUid();
    if (!_supported || uid == null) return right(unit);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(registeredKey(uid));
    try {
      final id = await _deviceId();
      await _device(uid, id).delete().timeout(_writeTimeout);
      return right(unit);
    } on Object catch (e) {
      _log('device removal failed: $e');
      return left(Failure.unexpected('device removal failed: $e'));
    } finally {
      // The old token stops working, so nothing reaches this device even if
      // its document could not be deleted. The next sign-in gets a new one.
      try {
        // ignore: deprecated_member_use
        await _messaging().deleteToken().timeout(_writeTimeout);
      } on Object catch (e) {
        _log('token removal failed: $e');
      }
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteAllDevices() async {
    final uid = _currentUid();
    if (uid == null) return right(unit);
    try {
      final devices = await _firestore
          .collection('users')
          .doc(uid)
          .collection('devices')
          .get();
      final batch = _firestore.batch();
      for (final doc in devices.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      await (await SharedPreferences.getInstance()).remove(registeredKey(uid));
      return right(unit);
    } on FirebaseException catch (e) {
      return left(Failure.unexpected('${e.code} ${e.message}'));
    }
  }

  static NotificationOpen toOpen(RemoteMessage message) {
    final data = message.data;
    String? text(String key) =>
        data[key] is String ? data[key] as String : null;
    return NotificationOpen(
      messageId: text('messageId'),
      category: NotificationCategory.fromId(text('category')),
      route: parseNotificationRoute(text('route')),
      source: parseNotificationSource(text('source')),
    );
  }

  @override
  Future<NotificationOpen?> initialOpen() async {
    if (!_supported) return null;
    try {
      final message = await _messaging().getInitialMessage();
      return message == null ? null : toOpen(message);
    } on Object catch (e) {
      _log('initial message unavailable: $e');
      return null;
    }
  }

  @override
  Stream<NotificationOpen> opens() =>
      _supported ? _openedMessages().map(toOpen) : const Stream.empty();

  @override
  Future<void> setUpChannels(List<NotificationChannelSpec> channels) async {
    if (platform != 'android') return;
    try {
      await _createChannels([
        for (final c in channels)
          {'id': c.category.id, 'name': c.name, 'description': c.description},
      ]);
    } on Object catch (e) {
      _log('channels not created: $e');
    }
  }
}
