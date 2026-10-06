import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/repositories/firestore_invite_repository.dart';
import 'package:simsplit/domain/failures/invite_failure.dart';
import 'package:simsplit/domain/failures/sync_failure.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase database;
  late FakeFirebaseFirestore cloud;
  var uid = 'alice';
  var tokens = 0;

  FirestoreInviteRepository repository() => FirestoreInviteRepository(
        database: database,
        firestore: cloud,
        currentUid: () => uid,
        linkBase: Uri.parse('https://simsplit.web.app/join'),
        newId: () => 'activity1',
        newToken: () => 'token${++tokens}',
      );

  Future<void> seedLocalGroup({String? inviteToken}) =>
      database.into(database.groups).insert(GroupsCompanion.insert(
            id: 'g1',
            name: 'Trip',
            colorValue: 0,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            inviteToken: Value(inviteToken),
          ));

  Future<void> seedCloudGroup(List<String> uids, {String? inviteToken}) async {
    await cloud.doc('groups/g1').set({
      'name': 'Trip',
      'ownerUid': uids.first,
      'memberUids': uids,
      'inviteToken': inviteToken,
    });
    await cloud
        .doc('groups/g1/members/m1')
        .set({'name': 'An', 'linkedUid': uids.first});
    if (inviteToken != null) {
      await cloud.doc('invites/$inviteToken').set({'groupId': 'g1'});
    }
  }

  Future<void> queueLocalChange() => database.syncDao.enqueue(
        ActivitiesCompanion.insert(
          id: 'a1',
          groupId: 'g1',
          actorUid: 'alice',
          action: 'create',
          entityType: 'expense',
          entityId: 'e1',
          after: '{}',
          clientTime: DateTime(2026),
        ),
      );

  setUp(() {
    uid = 'alice';
    tokens = 0;
    database = AppDatabase.forTesting(NativeDatabase.memory());
    cloud = FakeFirebaseFirestore();
  });

  tearDown(() => database.close());

  group('inviteLink (AC9)', () {
    test('creates the first link with its invite document', () async {
      await seedLocalGroup();
      await seedCloudGroup(['alice']);

      final link = (await repository().inviteLink('g1')).toNullable();

      expect(link.toString(), 'https://simsplit.web.app/join/token1');
      expect((await cloud.doc('groups/g1').get()).data()!['inviteToken'],
          'token1');
      expect(
          (await cloud.doc('invites/token1').get()).data(), {'groupId': 'g1'});
      expect(
          (await database.groupDao.getGroupById('g1'))!.inviteToken, 'token1');
    });

    test('reuses the existing link, without the network when known', () async {
      await seedLocalGroup(inviteToken: 'known');

      final link = (await repository().inviteLink('g1')).toNullable();

      expect(link.toString(), 'https://simsplit.web.app/join/known');
      expect(tokens, 0);
    });

    test('refuses while the group has not reached the cloud', () async {
      await seedLocalGroup();
      await queueLocalChange();

      final result = await repository().inviteLink('g1');

      expect(result.getLeft().toNullable(), isA<SyncUnsyncedChanges>());
    });
  });

  test('resetInviteLink replaces the link and removes the old one (AC13)',
      () async {
    await seedLocalGroup(inviteToken: 'old');
    await seedCloudGroup(['alice'], inviteToken: 'old');

    final link = (await repository().resetInviteLink('g1')).toNullable();

    expect(link.toString(), 'https://simsplit.web.app/join/token1');
    expect((await cloud.doc('invites/old').get()).exists, isFalse);
    expect((await cloud.doc('invites/token1').get()).exists, isTrue);
    expect((await database.groupDao.getGroupById('g1'))!.inviteToken, 'token1');
  });

  group('joinGroup (AC10)', () {
    test('adds the account with the token and logs it', () async {
      await seedCloudGroup(['alice'], inviteToken: 'tok');
      uid = 'bob';

      final result = await repository().joinGroup('tok');

      expect(result.toNullable(), 'g1');
      final group = (await cloud.doc('groups/g1').get()).data()!;
      expect(group['memberUids'], ['alice', 'bob']);
      expect(group['joinToken'], 'tok');
      final activity =
          (await cloud.doc('groups/g1/activity/activity1').get()).data()!;
      expect((activity['actorUid'], activity['action']), ('bob', 'join'));
    });

    test('reports an unknown or reset link', () async {
      uid = 'bob';

      final result = await repository().joinGroup('nope');

      expect(result.getLeft().toNullable(), isA<InviteInvalidLink>());
    });

    test('does nothing for a group already on this device', () async {
      await seedLocalGroup();
      await seedCloudGroup(['alice'], inviteToken: 'tok');

      expect((await repository().joinGroup('tok')).toNullable(), 'g1');
      expect((await cloud.doc('groups/g1').get()).data()!['memberUids'],
          ['alice']);
    });
  });

  group('leaveGroup (AC14)', () {
    test('releases the member and leaves, handing over ownership', () async {
      await seedLocalGroup();
      await seedCloudGroup(['alice', 'bob']);

      final result = await repository().leaveGroup('g1');

      expect(result.isRight(), isTrue);
      final group = (await cloud.doc('groups/g1').get()).data()!;
      expect(group['memberUids'], ['bob']);
      expect(group['ownerUid'], 'bob');
      expect(
          (await cloud.doc('groups/g1/members/m1').get()).data()!['linkedUid'],
          isNull);
    });

    test('refuses while changes have not reached the cloud', () async {
      await seedLocalGroup();
      await seedCloudGroup(['alice', 'bob']);
      await queueLocalChange();

      final result = await repository().leaveGroup('g1');

      expect(result.getLeft().toNullable(), isA<SyncUnsyncedChanges>());
      expect((await cloud.doc('groups/g1').get()).data()!['memberUids'],
          ['alice', 'bob']);
    });
  });
}
