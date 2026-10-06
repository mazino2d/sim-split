import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/sync/firestore_sync_puller.dart';

const _alice = 'alice';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase database;
  late FakeFirebaseFirestore cloud;
  late FirestoreSyncPuller puller;

  final t0 = DateTime(2026, 10, 1, 12).millisecondsSinceEpoch;

  DocumentReference<Map<String, dynamic>> groupDoc(String id) =>
      cloud.collection('groups').doc(id);

  Future<void> putGroup(String id, {List<String> uids = const [_alice]}) =>
      groupDoc(id).set({
        'name': 'Da Lat trip',
        'emoji': null,
        'colorValue': 1,
        'currencyCode': 'VND',
        'isArchived': false,
        'createdAt': t0,
        'createdBy': _alice,
        'updatedBy': _alice,
        'deleted': false,
        'ownerUid': uids.first,
        'memberUids': uids,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> putMember(String group, String id, {String? linkedUid}) =>
      groupDoc(group).collection('members').doc(id).set({
        'name': id,
        'avatarColorValue': 2,
        'emoji': null,
        'linkedUid': linkedUid,
        'createdAt': t0,
        'createdBy': _alice,
        'updatedBy': _alice,
        'deleted': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> putExpense(
    String group,
    String id, {
    int amountCents = 30000000,
    Map<String, int>? shares,
    bool deleted = false,
    String updatedBy = _alice,
  }) {
    final splits = shares ?? {'khoi': 15000000, 'linh': 15000000};
    return groupDoc(group).collection('expenses').doc(id).set({
      'title': 'Hotpot',
      'amountCents': amountCents,
      'currencyCode': 'VND',
      'paidByMemberId': 'khoi',
      'splitType': 'exact',
      'category': 'food',
      'note': null,
      'expenseDate': t0,
      'createdAt': t0,
      'editedAt': t0 + 60000,
      'createdBy': _alice,
      'updatedBy': updatedBy,
      'deleted': deleted,
      'splits': [
        for (final MapEntry(key: member, value: cents) in splits.entries)
          {
            'id': '$id-$member',
            'memberId': member,
            'value': cents,
            'amountCents': cents
          },
      ],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> putSettlement(String group, String id) =>
      groupDoc(group).collection('settlements').doc(id).set({
        'fromMemberId': 'linh',
        'toMemberId': 'khoi',
        'amountCents': 15000000,
        'currencyCode': 'VND',
        'note': null,
        'settledAt': t0,
        'createdAt': t0,
        'createdBy': _alice,
        'updatedBy': _alice,
        'deleted': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// A group shared by Alice and Bob: Khoi (Alice) and Linh, one expense
  /// and one settlement.
  Future<void> seedTrip() async {
    await putGroup('g1', uids: [_alice, 'bob']);
    await putMember('g1', 'khoi', linkedUid: _alice);
    await putMember('g1', 'linh', linkedUid: 'bob');
    await putExpense('g1', 'e1');
    await putSettlement('g1', 's1');
  }

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await puller.idle();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<List<ExpenseSplit>> splitsOf(String expenseId) =>
      database.expenseSplitDao.getSplitsForExpense(expenseId);

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    cloud = FakeFirebaseFirestore();
    puller = FirestoreSyncPuller(database: database, firestore: cloud);
  });

  tearDown(() async {
    await puller.stop();
    await database.close();
  });

  test('pulls the account\'s groups with everything in them', () async {
    await seedTrip();
    await putGroup('other', uids: ['carol']);

    puller.start(_alice);
    await settle();

    final groups = await database.select(database.groups).get();
    expect(groups.map((g) => g.id), ['g1']);
    expect(groups.single.name, 'Da Lat trip');

    final members = await database.memberDao.getMembersByGroup('g1');
    expect(
        {for (final m in members) m.id: m.isMe}, {'khoi': true, 'linh': false});
    expect(members.firstWhere((m) => m.id == 'linh').linkedUid, 'bob');

    final expense = (await database.expenseDao.getExpenseById('e1'))!;
    expect(expense.amountCents, 30000000);
    expect(expense.updatedAt.millisecondsSinceEpoch, t0 + 60000);
    final splits = await splitsOf('e1');
    expect(splits.map((s) => s.amountCents).fold(0, (a, b) => a + b),
        expense.amountCents);

    expect(await database.settlementDao.getSettlementById('s1'), isNotNull);
  });

  test('applies remote edits in real time, expense and splits together',
      () async {
    await seedTrip();
    puller.start(_alice);
    await settle();

    await putExpense('g1', 'e1',
        amountCents: 36000000,
        shares: {'khoi': 6000000, 'linh': 30000000},
        updatedBy: 'bob');
    await settle();

    final expense = (await database.expenseDao.getExpenseById('e1'))!;
    expect(expense.amountCents, 36000000);
    expect(expense.updatedBy, 'bob');
    expect({for (final s in await splitsOf('e1')) s.memberId: s.amountCents},
        {'khoi': 6000000, 'linh': 30000000});
  });

  test('pulls a deletion as a tombstone', () async {
    await seedTrip();
    puller.start(_alice);
    await settle();

    await putExpense('g1', 'e1', deleted: true);
    await settle();

    expect((await database.expenseDao.getExpenseById('e1'))!.isDeleted, isTrue);
    expect(await database.expenseDao.watchExpensesByGroup('g1').first, isEmpty);
  });

  test('keeps local records whose changes are still waiting to be pushed',
      () async {
    await seedTrip();
    puller.start(_alice);
    await settle();

    // A local edit that has not reached the server yet.
    await database.expenseDao.updateExpenseById(
        const ExpensesCompanion(id: Value('e1'), amountCents: Value(50000000)));
    await database.syncDao.enqueue(ActivitiesCompanion.insert(
      id: 'a1',
      groupId: 'g1',
      actorUid: _alice,
      action: 'update',
      entityType: 'expense',
      entityId: 'e1',
      after: '{}',
      clientTime: DateTime(2026, 10, 2),
    ));

    await putExpense('g1', 'e1', amountCents: 36000000, updatedBy: 'bob');
    await settle();

    expect((await database.expenseDao.getExpenseById('e1'))!.amountCents,
        50000000);
  });

  test('never queues pulled changes for push', () async {
    await seedTrip();
    puller.start(_alice);
    await settle();

    expect(await database.syncDao.pendingCount(), 0);
  });

  test('applies an expense once the member it names arrives', () async {
    await seedTrip();
    puller.start(_alice);
    await settle();

    await putExpense('g1', 'e2', shares: {'khoi': 15000000, 'minh': 15000000});
    await settle();
    expect(await database.expenseDao.getExpenseById('e2'), isNull);

    await putMember('g1', 'minh');
    await settle();
    expect(await database.expenseDao.getExpenseById('e2'), isNotNull);
  });

  test('removes a group the account left on another device', () async {
    await seedTrip();
    puller.start(_alice);
    await settle();

    await groupDoc('g1').update({
      'memberUids': ['bob']
    });
    await settle();

    expect(await database.select(database.groups).get(), isEmpty);
    expect(await database.select(database.expenses).get(), isEmpty);
  });

  test('after a restart, removes groups left while it was stopped', () async {
    await seedTrip();
    puller.start(_alice);
    await settle();
    await puller.stop();

    await groupDoc('g1').update({
      'memberUids': ['bob']
    });
    puller.start(_alice);
    await settle();

    expect(await database.select(database.groups).get(), isEmpty);
  });

  test('after a restart, pulls only what changed meanwhile', () async {
    await seedTrip();
    puller.start(_alice);
    await settle();
    await puller.stop();

    // A local copy that a full re-pull would overwrite.
    await database.expenseDao.updateExpenseById(
        const ExpensesCompanion(id: Value('e1'), title: Value('Kept locally')));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await putSettlement('g1', 's2');

    puller.start(_alice);
    await settle();

    expect((await database.expenseDao.getExpenseById('e1'))!.title,
        'Kept locally');
    expect(await database.settlementDao.getSettlementById('s2'), isNotNull);
  });

  test('stops applying changes once stopped', () async {
    await seedTrip();
    puller.start(_alice);
    await settle();
    await puller.stop();

    await putExpense('g1', 'e1', amountCents: 1);
    await settle();

    expect((await database.expenseDao.getExpenseById('e1'))!.amountCents,
        30000000);
  });
}
