import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/notification_prefs_repository.dart';

/// `users/{uid}.notificationPrefs` (R-9 AC3, AC26–AC32). Every field is
/// optional and a missing one means its default:
///
/// - `groupActivity`, `settleReminder`, `updates`: bools (defaults in
///   `crm/categories.yaml`);
/// - `activityEvents`: bools by event (`expenseCreate`, …);
/// - `onlyInvolvingMe`: bool; `bundle`: `10m`, `30m`, `1h` or `daily`;
/// - `groups`: groupId → `{mode: all | involving | off, offUntil?}`, at
///   most 200; a missing group is `all`;
/// - `pausedUntil`: Timestamp;
/// - `quietHours`: `{from, to}` as `HH:MM`; `settle`: `{day, time, minDays}`;
/// - `mutedGroups`: group IDs muted before settings v2, read once to move
///   them into `groups`, never written.
///
/// The rules let only the account change it, with these keys and types.
class FirestoreNotificationPrefsRepository
    implements NotificationPrefsRepository {
  const FirestoreNotificationPrefsRepository({
    required FirebaseFirestore firestore,
    required String? Function() currentUid,
  })  : _firestore = firestore,
        _currentUid = currentUid;

  final FirebaseFirestore _firestore;
  final String? Function() _currentUid;

  static const field = 'notificationPrefs';

  /// A change made offline stays queued; the screen keeps its new state
  /// from the local snapshot and the write goes out once online.
  static const _ackTimeout = Duration(seconds: 5);

  static Map<String, Object?> _map(Object? raw) => raw is Map
      ? {
          for (final e in raw.entries)
            if (e.key is String) e.key as String: e.value,
        }
      : const {};

  static DateTime? _time(Object? raw) => raw is Timestamp ? raw.toDate() : null;

  static NotificationPrefs parse(Object? raw) {
    if (raw is! Map) return const NotificationPrefs();
    final muted = raw['mutedGroups'];
    final events = _map(raw['activityEvents']);
    final quiet = _map(raw['quietHours']);
    final settle = _map(raw['settle']);
    final quietFrom = DayTime.parse(quiet['from']);
    final quietTo = DayTime.parse(quiet['to']);
    final settleDay = settle['day'];
    final settleTime = DayTime.parse(settle['time']);
    final minDays = settle['minDays'];
    return NotificationPrefs(
      categories: {
        for (final c in NotificationCategory.values)
          if (raw[c.prefKey] is bool) c: raw[c.prefKey] as bool,
      },
      activityEvents: {
        for (final e in ActivityEvent.values)
          if (events[e.name] is bool) e: events[e.name] as bool,
      },
      onlyInvolvingMe: raw['onlyInvolvingMe'] == true,
      bundle: ActivityBundle.fromWire(raw['bundle']),
      groups: {
        for (final e in _map(raw['groups']).entries)
          if (GroupNotifyMode.fromWire(_map(e.value)['mode']) case final mode?)
            e.key: GroupNotifySetting(mode,
                offUntil: _time(_map(e.value)['offUntil'])),
      },
      legacyMutedGroups:
          muted is List ? muted.whereType<String>().toList() : const [],
      pausedUntil: _time(raw['pausedUntil']),
      quietHours: QuietHours(
        from: quietFrom != null && QuietHours.validFrom(quietFrom)
            ? quietFrom
            : QuietHours.defaultFrom,
        to: quietTo != null && QuietHours.validTo(quietTo)
            ? quietTo
            : QuietHours.defaultTo,
      ),
      settle: SettleReminderPrefs(
        day: settleDay is int && settleDay >= 0 && settleDay <= 6
            ? settleDay
            : 0,
        time: settleTime != null && SettleReminderPrefs.validTime(settleTime)
            ? settleTime
            : SettleReminderPrefs.defaultTime,
        minDays: SettleReminderPrefs.minDaysChoices.contains(minDays)
            ? minDays as int
            : 14,
      ),
    );
  }

  static Map<String, Object> _group(GroupNotifySetting setting) => {
        'mode': setting.mode.wire,
        if (setting.offUntil case final until?)
          'offUntil': Timestamp.fromDate(until),
      };

  @override
  Stream<Either<Failure, NotificationPrefs>> watchPrefs() {
    final uid = _currentUid();
    if (uid == null) return Stream.value(right(const NotificationPrefs()));
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map<Either<Failure, NotificationPrefs>>(
            (doc) => right(parse(doc.data()?[field])))
        .transform(StreamTransformer.fromHandlers(
          handleError: (error, stackTrace, sink) =>
              sink.add(left(Failure.unexpected(error.toString()))),
        ));
  }

  Future<Either<Failure, Unit>> _update(Map<Object, Object> changes) async {
    final uid = _currentUid();
    if (uid == null) return left(const Failure.unexpected('Not signed in'));
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .update(changes)
          .timeout(_ackTimeout);
      return right(unit);
    } on TimeoutException {
      return right(unit);
    } on FirebaseException catch (e) {
      return left(Failure.unexpected('${e.code} ${e.message}'));
    }
  }

  @override
  Future<Either<Failure, Unit>> setCategory(
          NotificationCategory category, bool on) =>
      _update({'$field.${category.prefKey}': on});

  @override
  Future<Either<Failure, Unit>> setActivityEvent(
          ActivityEvent event, bool on) =>
      _update({'$field.activityEvents.${event.name}': on});

  @override
  Future<Either<Failure, Unit>> setOnlyInvolvingMe(bool on) =>
      _update({'$field.onlyInvolvingMe': on});

  @override
  Future<Either<Failure, Unit>> setBundle(ActivityBundle bundle) =>
      _update({'$field.bundle': bundle.wire});

  @override
  Future<Either<Failure, Unit>> setGroup(
          String groupId, GroupNotifySetting? setting) =>
      _update({
        // A missing group is All activity.
        FieldPath([field, 'groups', groupId]):
            setting == null ? FieldValue.delete() : _group(setting),
      });

  @override
  Future<Either<Failure, Unit>> migrateMutedGroups(
      List<String> groupIds, Map<String, GroupNotifySetting> current) {
    final room = maxGroupSettings - current.length;
    final moved = groupIds
        .where((g) => !current.containsKey(g))
        .toSet()
        .take(room < 0 ? 0 : room);
    return _update({
      for (final g in moved)
        FieldPath([field, 'groups', g]):
            _group(const GroupNotifySetting(GroupNotifyMode.off)),
      '$field.mutedGroups': FieldValue.delete(),
    });
  }

  @override
  Future<Either<Failure, Unit>> setPausedUntil(DateTime? until) => _update({
        '$field.pausedUntil':
            until == null ? FieldValue.delete() : Timestamp.fromDate(until),
      });

  @override
  Future<Either<Failure, Unit>> setQuietHours(QuietHours quietHours) =>
      _update({
        // Absent is the policy, 21:00–08:00.
        '$field.quietHours': quietHours.isDefault
            ? FieldValue.delete()
            : {'from': quietHours.from.hhmm, 'to': quietHours.to.hhmm},
      });

  @override
  Future<Either<Failure, Unit>> setSettleReminder(SettleReminderPrefs settle) =>
      _update({
        '$field.settle': {
          'day': settle.day,
          'time': settle.time.hhmm,
          'minDays': settle.minDays,
        },
      });
}
