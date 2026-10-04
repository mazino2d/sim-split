import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide Group;
import 'package:simsplit/data/database/app_database.dart' as db;
import 'package:simsplit/data/mappers/expense_mapper.dart';
import 'package:simsplit/data/mappers/group_mapper.dart';
import 'package:simsplit/data/mappers/member_mapper.dart';
import 'package:simsplit/data/repositories/drift_expense_repository.dart';
import 'package:simsplit/data/repositories/drift_group_repository.dart';
import 'package:simsplit/data/repositories/drift_member_repository.dart';
import 'package:simsplit/data/sync/firestore_sync_pusher.dart';
import 'package:simsplit/data/sync/sync_recorder.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

import '../../../helpers/mocks.dart';

T _right<T>(Either<Failure, T> result) =>
    result.getOrElse((f) => throw StateError('Unexpected failure: $f'));

/// A Firestore whose batch commits fail with [code] while [failing] is set.
class _FlakyFirestore extends Fake implements FirebaseFirestore {
  _FlakyFirestore(this._inner);

  final FakeFirebaseFirestore _inner;
  String? failing;
  int commits = 0;

  @override
  WriteBatch batch() => _FlakyBatch(this, _inner.batch());

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _inner.collection(path);
}

class _FlakyBatch extends Fake implements WriteBatch {
  _FlakyBatch(this._owner, this._inner);

  final _FlakyFirestore _owner;
  final WriteBatch _inner;

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) =>
      _inner.set(document, data, options);

  @override
  Future<void> commit() async {
    _owner.commits++;
    final code = _owner.failing;
    if (code != null) {
      throw FirebaseException(plugin: 'cloud_firestore', code: code);
    }
    await _inner.commit();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late db.AppDatabase database;
  late FakeFirebaseFirestore cloud;
  late _FlakyFirestore firestore;
  late FirestoreSyncPusher pusher;
  late DriftGroupRepository groups;
  late DriftMemberRepository members;
  late DriftExpenseRepository expenses;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    cloud = FakeFirebaseFirestore();
    firestore = _FlakyFirestore(cloud);
    pusher = FirestoreSyncPusher(
      syncDao: database.syncDao,
      firestore: firestore,
      retryDelay: (_) => const Duration(milliseconds: 10),
    );
    var nextId = 0;
    final recorder = SyncRecorder(
      syncDao: database.syncDao,
      currentUid: () => 'alice',
      clock: () => DateTime.utc(2026, 10, 4),
      newId: () => 'a${nextId++}',
    );
    groups = DriftGroupRepository(
        groupDao: database.groupDao,
        mapper: const GroupMapper(),
        recorder: recorder);
    members = DriftMemberRepository(
        memberDao: database.memberDao,
        mapper: const MemberMapper(),
        recorder: recorder);
    expenses = DriftExpenseRepository(
        expenseDao: database.expenseDao,
        expenseSplitDao: database.expenseSplitDao,
        mapper: const ExpenseMapper(),
        recorder: recorder);
  });

  tearDown(() async {
    await pusher.stop();
    await database.close();
  });

  Future<void> seed() async {
    _right(await groups.createGroup(testGroup()));
    _right(await members.addMember(testMember('m1').copyWith(isMe: true)));
    _right(await members.addMember(testMember('m2')));
    _right(await expenses.addExpense(testExpense(splits: [
      const ExpenseSplit(
          id: 's1',
          expenseId: 'e1',
          memberId: 'm1',
          value: 3333,
          amountCents: 3333),
      const ExpenseSplit(
          id: 's2',
          expenseId: 'e1',
          memberId: 'm2',
          value: 6667,
          amountCents: 6667),
    ])));
  }

  Future<void> drained() async {
    // Let the pending-count stream fire, then wait for the drain.
    await pumpEventQueue();
    await pusher.idle();
  }

  test('pushes each change with its activity entry and empties the outbox',
      () async {
    await seed();
    pusher.start();
    await drained();

    expect(await database.syncDao.pendingCount(), 0);

    final group = (await cloud.doc('groups/g1').get()).data()!;
    expect(group['name'], 'Group g1');
    expect(group['ownerUid'], 'alice');
    expect(group['memberUids'], ['alice']);
    expect(group['updatedBy'], 'alice');
    expect(group['updatedAt'], isNotNull);

    final m1 = (await cloud.doc('groups/g1/members/m1').get()).data()!;
    expect(m1['linkedUid'], 'alice');
    expect(m1.containsKey('isMe'), isFalse);

    final expense = (await cloud.doc('groups/g1/expenses/e1').get()).data()!;
    expect(expense['amountCents'], 10000);
    expect(
      (expense['splits'] as List).map((s) => (s as Map)['amountCents']),
      [3333, 6667],
    );

    final activity = await cloud.collection('groups/g1/activity').get();
    expect(activity.docs, hasLength(4));
    final created = activity.docs.firstWhere((d) => d['entityId'] == 'e1');
    expect(created['action'], 'create');
    expect(created['actorUid'], 'alice');
    expect(created['before'], isNull);
    expect(created['clientTime'],
        DateTime.utc(2026, 10, 4).millisecondsSinceEpoch);
  });

  test('pushes changes made while running, in order', () async {
    await seed();
    pusher.start();
    await drained();

    _right(await expenses.updateExpense(testExpense(amountCents: 9000, splits: [
      const ExpenseSplit(
          id: 's3',
          expenseId: 'e1',
          memberId: 'm2',
          value: 9000,
          amountCents: 9000),
    ])));
    _right(await expenses.deleteExpense('e1'));
    await drained();

    final expense = (await cloud.doc('groups/g1/expenses/e1').get()).data()!;
    expect(expense['amountCents'], 9000);
    expect(expense['deleted'], isTrue);
    expect(await database.syncDao.pendingCount(), 0);
  });

  test('a group update keeps the members and owner set in the cloud', () async {
    await seed();
    pusher.start();
    await drained();
    await cloud.doc('groups/g1').update({
      'memberUids': ['alice', 'bob'],
    });

    _right(await groups.updateGroup(testGroup().copyWith(name: 'Trip')));
    await drained();

    final group = (await cloud.doc('groups/g1').get()).data()!;
    expect(group['name'], 'Trip');
    expect(group['memberUids'], ['alice', 'bob']);
  });

  test('keeps changes queued while offline and retries (AC16)', () async {
    await seed();
    firestore.failing = 'unavailable';
    pusher.start();
    await drained();

    expect(await database.syncDao.pendingCount(), 4);
    expect((await cloud.doc('groups/g1').get()).exists, isFalse);

    firestore.failing = null;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await pusher.idle();

    expect(await database.syncDao.pendingCount(), 0);
    expect((await cloud.doc('groups/g1/expenses/e1').get()).exists, isTrue);
  });

  test('drops changes the server already has after a restart', () async {
    await seed();
    pusher.start();
    await drained();
    await pusher.stop();

    // The app was killed before the outbox was cleared: the same entries
    // are queued again and their activity entries already exist.
    final again = await database.select(database.activities).get();
    for (final activity in again) {
      await database.into(database.outboxEntries).insert(
            db.OutboxEntriesCompanion.insert(
              groupId: activity.groupId,
              activityId: activity.id,
            ),
          );
    }
    // Security rules reject re-creating an activity entry.
    firestore.failing = 'permission-denied';
    pusher.start();
    await drained();

    expect(await database.syncDao.pendingCount(), 0);
    expect(
      await (database.select(database.outboxEntries)
            ..where((o) => o.failed.equals(true)))
          .get(),
      isEmpty,
    );
  });

  test('sets a rejected change aside so the rest can go through', () async {
    await seed();
    firestore.failing = 'permission-denied';
    pusher.start();
    await drained();

    // Every entry was rejected in turn and set aside, none left blocking.
    expect(await database.syncDao.pendingCount(), 0);
    expect(await database.select(database.outboxEntries).get(), hasLength(4));
  });
}
