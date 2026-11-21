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

  test('an account without choices gets the defaults (AC3)', () async {
    final prefs = await current();
    expect(prefs, const NotificationPrefs());
    expect(prefs.isOn(NotificationCategory.groupActivity), isTrue);
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

  test('muting adds the group once, unmuting removes it (AC4)', () async {
    await repo.setGroupMuted('g1', true);
    await repo.setGroupMuted('g1', true);
    await repo.setGroupMuted('g2', true);
    expect((await stored())!['mutedGroups'], ['g1', 'g2']);

    await repo.setGroupMuted('g1', false);
    expect((await current()).isMuted('g1'), isFalse);
    expect((await current()).isMuted('g2'), isTrue);
  });

  test('ignores fields of the wrong type', () {
    final prefs = FirestoreNotificationPrefsRepository.parse({
      'groupActivity': 'yes',
      'updates': true,
      'mutedGroups': ['g1', 7],
    });
    expect(prefs.isOn(NotificationCategory.groupActivity), isTrue);
    expect(prefs.isOn(NotificationCategory.updates), isTrue);
    expect(prefs.mutedGroups, ['g1']);
  });
}
