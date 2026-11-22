import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/data/notifications/firestore_notification_prefs_repository.dart';
import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreNotificationPrefsRepository repo;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc('users/alice').set({'displayName': 'Alice'});
    repo = FirestoreNotificationPrefsRepository(
        firestore: firestore, currentUid: () => 'alice');
  });

  Future<NotificationPrefs> current() async =>
      (await repo.watchPrefs().first).getOrElse((f) => fail('$f'));

  Future<Map<String, dynamic>?> stored() async =>
      (await firestore.doc('users/alice').get()).data()?['notificationPrefs']
          as Map<String, dynamic>?;

  final now = DateTime(2026, 11, 22, 21, 30);

  test('an account without choices gets the defaults (AC3, AC26–AC32)',
      () async {
    final prefs = await current();
    expect(prefs, const NotificationPrefs());
    expect(prefs.isOn(NotificationCategory.groupActivity), isTrue);
    expect(prefs.isEventOn(ActivityEvent.expenseCreate), isTrue);
    expect(prefs.isEventOn(ActivityEvent.memberJoin), isFalse);
    expect(prefs.onlyInvolvingMe, isFalse);
    expect(prefs.bundle, ActivityBundle.tenMinutes);
    expect(prefs.groupChoice('g1', now), GroupNotifyChoice.all);
    expect(prefs.pausedAt(now), isNull);
    expect(prefs.quietHours.from.hhmm, '21:00');
    expect(prefs.quietHours.to.hhmm, '08:00');
    expect((prefs.settle.day, prefs.settle.time.hhmm, prefs.settle.minDays),
        (0, '19:00', 14));
  });

  test('a switch writes only its own field', () async {
    await repo.setCategory(NotificationCategory.settleReminder, true);
    await repo.setCategory(NotificationCategory.groupActivity, false);

    expect(await stored(), {'settleReminder': true, 'groupActivity': false});
    final prefs = await current();
    expect(prefs.isOn(NotificationCategory.settleReminder), isTrue);
    expect(prefs.isOn(NotificationCategory.groupActivity), isFalse);
    expect(prefs.isOn(NotificationCategory.updates), isFalse);
  });

  test('event switches, involvement and bundle use the contract keys',
      () async {
    await repo.setActivityEvent(ActivityEvent.expenseDelete, false);
    await repo.setActivityEvent(ActivityEvent.memberJoin, true);
    await repo.setOnlyInvolvingMe(true);
    await repo.setBundle(ActivityBundle.daily);

    expect(await stored(), {
      'activityEvents': {'expenseDelete': false, 'memberJoin': true},
      'onlyInvolvingMe': true,
      'bundle': 'daily',
    });
    final prefs = await current();
    expect(prefs.isEventOn(ActivityEvent.expenseDelete), isFalse);
    expect(prefs.isEventOn(ActivityEvent.memberJoin), isTrue);
    expect(prefs.isEventOn(ActivityEvent.settlement), isTrue);
    expect(prefs.onlyInvolvingMe, isTrue);
    expect(prefs.bundle, ActivityBundle.daily);
  });

  test('a group choice is stored as a mode; All activity removes it (AC29)',
      () async {
    final until = DateTime(2026, 11, 23, 8);
    await repo.setGroup(
        'g-1', const GroupNotifySetting(GroupNotifyMode.involving));
    await repo.setGroup(
        'g2', GroupNotifySetting(GroupNotifyMode.off, offUntil: until));
    await repo.setGroup('g3', const GroupNotifySetting(GroupNotifyMode.off));

    expect((await stored())!['groups'], {
      'g-1': {'mode': 'involving'},
      'g2': {'mode': 'off', 'offUntil': Timestamp.fromDate(until)},
      'g3': {'mode': 'off'},
    });
    var prefs = await current();
    expect(prefs.groupChoice('g-1', now), GroupNotifyChoice.involving);
    expect(prefs.groupChoice('g2', now), GroupNotifyChoice.offUntilMorning);
    expect(prefs.groupChoice('g3', now), GroupNotifyChoice.off);
    // Once 08:00 has passed, the group is back to All activity.
    expect(prefs.groupChoice('g2', DateTime(2026, 11, 23, 8, 1)),
        GroupNotifyChoice.all);

    await repo.setGroup('g-1', null);
    prefs = await current();
    expect(prefs.groupChoice('g-1', now), GroupNotifyChoice.all);
    expect((await stored())!['groups'], isNot(contains('g-1')));
  });

  test('muted groups move to groups as Off and mutedGroups goes away',
      () async {
    await firestore.doc('users/alice').update({
      'notificationPrefs.mutedGroups': ['g1', 'g2'],
      'notificationPrefs.groups': {
        'g2': {'mode': 'involving'},
      },
    });
    var prefs = await current();
    expect(prefs.groupChoice('g1', now), GroupNotifyChoice.off);
    expect(prefs.isGroupSilenced('g1', now), isTrue);

    await repo.migrateMutedGroups(prefs.legacyMutedGroups, prefs.groups);

    final raw = await stored();
    expect(raw!.containsKey('mutedGroups'), isFalse);
    expect(raw['groups'], {
      'g1': {'mode': 'off'},
      // A newer choice wins.
      'g2': {'mode': 'involving'},
    });
    prefs = await current();
    expect(prefs.legacyMutedGroups, isEmpty);
    expect(prefs.groupChoice('g1', now), GroupNotifyChoice.off);
  });

  test('a pause is a timestamp; resuming deletes it (AC30)', () async {
    final until = now.add(const Duration(hours: 1));
    await repo.setPausedUntil(until);
    expect((await stored())!['pausedUntil'], Timestamp.fromDate(until));
    expect((await current()).pausedAt(now), until);
    expect((await current()).pausedAt(until), isNull);

    await repo.setPausedUntil(null);
    expect((await stored())!.containsKey('pausedUntil'), isFalse);
  });

  test('quiet hours and settle reminders are stored as HH:MM (AC31, AC32)',
      () async {
    await repo.setQuietHours(
        const QuietHours(from: DayTime(20 * 60), to: DayTime(9 * 60 + 30)));
    await repo.setSettleReminder(const SettleReminderPrefs(
        day: 5, time: DayTime(20 * 60 + 30), minDays: 30));
    expect(await stored(), {
      'quietHours': {'from': '20:00', 'to': '09:30'},
      'settle': {'day': 5, 'time': '20:30', 'minDays': 30},
    });
    final prefs = await current();
    expect(prefs.quietHours.from.hhmm, '20:00');
    expect(prefs.settle.time.hhmm, '20:30');

    // The default range is the policy: the field goes away.
    await repo.setQuietHours(const QuietHours());
    expect((await stored())!.containsKey('quietHours'), isFalse);
  });

  test('ignores fields of the wrong type or out of range', () {
    final prefs = FirestoreNotificationPrefsRepository.parse({
      'groupActivity': 'yes',
      'updates': true,
      'mutedGroups': ['g1', 7],
      'activityEvents': {'memberJoin': 'on', 'settlement': false},
      'onlyInvolvingMe': 'true',
      'bundle': '5m',
      'groups': {
        'a': {'mode': 'loud'},
        'b': 'off',
        'c': {'mode': 'off', 'offUntil': '08:00'},
      },
      'pausedUntil': '2026-12-01',
      'quietHours': {'from': '23:00', 'to': '09:00'},
      'settle': {'day': 9, 'time': '22:00', 'minDays': 10},
    });
    expect(prefs.isOn(NotificationCategory.groupActivity), isTrue);
    expect(prefs.isOn(NotificationCategory.updates), isTrue);
    expect(prefs.legacyMutedGroups, ['g1']);
    expect(prefs.isEventOn(ActivityEvent.memberJoin), isFalse);
    expect(prefs.isEventOn(ActivityEvent.settlement), isFalse);
    expect(prefs.onlyInvolvingMe, isFalse);
    expect(prefs.bundle, ActivityBundle.tenMinutes);
    expect(prefs.groups.keys, ['c']);
    expect(prefs.groupChoice('c', now), GroupNotifyChoice.off);
    expect(prefs.pausedUntil, isNull);
    expect(prefs.quietHours.from.hhmm, '21:00');
    expect(prefs.quietHours.to.hhmm, '09:00');
    expect(prefs.settle, const SettleReminderPrefs());
  });
}
