import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/repositories/firestore_sync_repository.dart';
import 'package:simsplit/data/sync/firestore_sync_puller.dart';
import 'package:simsplit/data/sync/firestore_sync_pusher.dart';
import 'package:simsplit/data/sync/local_data_uploader.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/sync_failure.dart';

/// Every request fails as it does without a connection.
class _OfflineFirestore extends Fake implements FirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase database;
  late FakeFirebaseFirestore cloud;
  late FirestoreSyncPusher pusher;
  late FirestoreSyncPuller puller;
  late FirestoreSyncRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    cloud = FakeFirebaseFirestore();
    pusher = FirestoreSyncPusher(syncDao: database.syncDao, firestore: cloud);
    puller = FirestoreSyncPuller(database: database, firestore: cloud);
    repository = FirestoreSyncRepository(
      syncDao: database.syncDao,
      uploader: LocalDataUploader(database: database),
      pusher: pusher,
      puller: puller,
      firestore: cloud,
      currentUid: () => 'alice',
      newId: () => 'leave1',
    );
  });

  tearDown(() async {
    await pusher.stop();
    await puller.stop();
    await database.close();
  });

  group('start / stop', () {
    test('marks the upload as done and starts pushing and pulling', () async {
      final result = await repository.start(const AuthUser(uid: 'alice'));

      expect(result.isRight(), isTrue);
      expect(pusher.isRunning, isTrue);
      expect(puller.isRunning, isTrue);
      expect(
        await database.syncDao.readState(LocalDataUploader.uploadedForKey),
        'alice',
      );

      await repository.stop();
      expect(pusher.isRunning, isFalse);
      expect(puller.isRunning, isFalse);
    });
  });

  group('deleteCloudData (AC6)', () {
    Future<void> seedSoloGroup() async {
      await cloud.doc('groups/solo').set({
        'name': 'Just me',
        'ownerUid': 'alice',
        'memberUids': ['alice'],
      });
      await cloud.doc('groups/solo/members/m1').set({'linkedUid': 'alice'});
      await cloud.doc('groups/solo/expenses/e1').set({'amountCents': 100});
      await cloud.doc('groups/solo/settlements/s1').set({'amountCents': 50});
      await cloud.doc('groups/solo/activity/a1').set({'action': 'create'});
    }

    Future<void> seedSharedGroup() async {
      await cloud.doc('groups/trip').set({
        'name': 'Trip',
        'ownerUid': 'alice',
        'memberUids': ['alice', 'bob'],
      });
      await cloud
          .doc('groups/trip/members/an')
          .set({'name': 'An', 'linkedUid': 'alice'});
      await cloud
          .doc('groups/trip/members/binh')
          .set({'name': 'Binh', 'linkedUid': 'bob'});
      await cloud
          .doc('groups/trip/expenses/e1')
          .set({'paidByMemberId': 'an', 'amountCents': 300});
    }

    test('deletes groups where the account is the only member', () async {
      await seedSoloGroup();

      final result = await repository.deleteCloudData();

      expect(result.isRight(), isTrue);
      expect((await cloud.doc('groups/solo').get()).exists, isFalse);
      for (final name in ['members', 'expenses', 'settlements', 'activity']) {
        expect(
            (await cloud.collection('groups/solo/$name').get()).docs, isEmpty,
            reason: name);
      }
    });

    test('leaves shared groups: the member and its expenses stay, unclaimed',
        () async {
      await seedSharedGroup();

      final result = await repository.deleteCloudData();

      expect(result.isRight(), isTrue);
      final group = (await cloud.doc('groups/trip').get()).data()!;
      expect(group['memberUids'], ['bob']);
      expect(group['ownerUid'], 'bob');
      final an = (await cloud.doc('groups/trip/members/an').get()).data()!;
      expect(an['name'], 'An');
      expect(an['linkedUid'], isNull);
      expect(
        (await cloud.doc('groups/trip/members/binh').get())['linkedUid'],
        'bob',
      );
      expect((await cloud.doc('groups/trip/expenses/e1').get()).exists, isTrue);

      final leave =
          (await cloud.doc('groups/trip/activity/leave1').get()).data()!;
      expect(leave['actorUid'], 'alice');
      expect(leave['entityId'], 'an');
      expect((leave['before'] as Map)['linkedUid'], 'alice');
      expect((leave['after'] as Map)['linkedUid'], isNull);
    });

    test('leaves groups of other people alone', () async {
      await cloud.doc('groups/other').set({
        'ownerUid': 'carol',
        'memberUids': ['carol'],
      });

      await repository.deleteCloudData();

      expect((await cloud.doc('groups/other').get()).exists, isTrue);
    });

    test('needs a connection, and resumes pushing when it fails', () async {
      final offline = FirestoreSyncRepository(
        syncDao: database.syncDao,
        uploader: LocalDataUploader(database: database),
        pusher: pusher,
        puller: puller,
        firestore: _OfflineFirestore(),
        currentUid: () => 'alice',
      );
      pusher.start();

      final result = await offline.deleteCloudData();

      expect(result.getLeft().toNullable(), isA<SyncNoConnection>());
      expect(pusher.isRunning, isTrue);
    });
  });
}
