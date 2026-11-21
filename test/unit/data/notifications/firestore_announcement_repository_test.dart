import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/data/notifications/firestore_announcement_repository.dart';
import 'package:simsplit/domain/entities/notifications/announcement.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreAnnouncementRepository repo;
  final now = DateTime(2026, 12, 1, 12);

  Map<String, dynamic> doc({
    bool all = false,
    List<String> uids = const [],
    int hours = 24,
  }) =>
      {
        'banner': {
          'en': {'title': 'New version', 'body': 'It fixes sync.'},
          'vi': {'title': 'Bản mới', 'body': 'Sửa lỗi đồng bộ.'},
        },
        'all': all,
        'audienceUids': uids,
        'endsAt': Timestamp.fromDate(now.add(Duration(hours: hours))),
      };

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc('users/alice').set({'displayName': 'Alice'});
    repo = FirestoreAnnouncementRepository(
        firestore: firestore, currentUid: () => 'alice', now: () => now);
  });

  test('reads banners for everyone and for the account, not ended (AC12)',
      () async {
    await firestore.doc('announcements/everyone').set(doc(all: true));
    await firestore.doc('announcements/mine').set(doc(uids: ['alice']));
    await firestore.doc('announcements/bobs').set(doc(uids: ['bob']));
    await firestore.doc('announcements/ended').set(doc(all: true, hours: -1));

    final list =
        (await repo.watchAnnouncements().first).getOrElse((f) => fail('$f'));

    expect(list.map((a) => a.id).toSet(), {'everyone', 'mine'});
    final mine = list.firstWhere((a) => a.id == 'mine');
    expect(mine.copyFor('vi')?.title, 'Bản mới');
    expect(mine.copyFor('en')?.body, 'It fixes sync.');
  });

  test('skips a banner without valid copy', () {
    expect(
        FirestoreAnnouncementRepository.parse('x1', {
          'banner': {'en': 'oops'},
          'endsAt': Timestamp.fromDate(now),
        }),
        isNull);
  });

  test('dismissing is kept with the account, once per banner', () async {
    await repo.dismiss('a1');
    await repo.dismiss('a1');
    await repo.dismiss('a2');

    expect((await firestore.doc('users/alice').get())['dismissedAnnouncements'],
        ['a1', 'a2']);
    expect((await repo.watchDismissed().first).getOrElse((f) => fail('$f')),
        {'a1', 'a2'});
  });

  test('keeps at most 100 dismissed banners, dropping the oldest', () async {
    await firestore.doc('users/alice').update({
      'dismissedAnnouncements': [
        for (var i = 0; i < maxDismissedAnnouncements; i++) 'c$i'
      ],
    });

    await repo.dismiss('new');

    final stored = (await firestore
        .doc('users/alice')
        .get())['dismissedAnnouncements'] as List;
    expect(stored, hasLength(maxDismissedAnnouncements));
    expect(stored.first, 'c1');
    expect(stored.last, 'new');
  });
}
