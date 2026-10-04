import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide Group;
import 'package:simsplit/data/database/app_database.dart' as db;
import 'package:simsplit/data/mappers/expense_mapper.dart';
import 'package:simsplit/data/mappers/group_mapper.dart';
import 'package:simsplit/data/mappers/member_mapper.dart';
import 'package:simsplit/data/mappers/settlement_mapper.dart';
import 'package:simsplit/data/repositories/drift_expense_repository.dart';
import 'package:simsplit/data/repositories/drift_group_repository.dart';
import 'package:simsplit/data/repositories/drift_member_repository.dart';
import 'package:simsplit/data/repositories/drift_settlement_repository.dart';
import 'package:simsplit/data/sync/local_data_uploader.dart';
import 'package:simsplit/data/sync/sync_recorder.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

import '../../../helpers/mocks.dart';

T _right<T>(Either<Failure, T> result) =>
    result.getOrElse((f) => throw StateError('Unexpected failure: $f'));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late db.AppDatabase database;
  late LocalDataUploader uploader;

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    uploader = LocalDataUploader(database: database);

    // v1 data, written while signed out.
    final recorder =
        SyncRecorder(syncDao: database.syncDao, currentUid: () => null);
    final groups = DriftGroupRepository(
        groupDao: database.groupDao,
        mapper: const GroupMapper(),
        recorder: recorder);
    final members = DriftMemberRepository(
        memberDao: database.memberDao,
        mapper: const MemberMapper(),
        recorder: recorder);
    final expenses = DriftExpenseRepository(
        expenseDao: database.expenseDao,
        expenseSplitDao: database.expenseSplitDao,
        mapper: const ExpenseMapper(),
        recorder: recorder);
    final settlements = DriftSettlementRepository(
        settlementDao: database.settlementDao,
        mapper: const SettlementMapper(),
        recorder: recorder);

    // g1: me + a friend, an expense, a settlement and a deleted expense.
    _right(await groups.createGroup(testGroup(id: 'g1')));
    _right(await members.addMember(testMember('m1').copyWith(isMe: true)));
    _right(await members.addMember(testMember('m2')));
    _right(await expenses.addExpense(testExpense(splits: [
      const ExpenseSplit(
          id: 's1',
          expenseId: 'e1',
          memberId: 'm2',
          value: 10000,
          amountCents: 10000),
    ])));
    _right(await expenses.addExpense(testExpense(id: 'gone', splits: [
      const ExpenseSplit(
          id: 's2',
          expenseId: 'gone',
          memberId: 'm2',
          value: 10000,
          amountCents: 10000),
    ])));
    _right(await expenses.deleteExpense('gone'));
    _right(await settlements.addSettlement(Settlement(
      id: 'st1',
      groupId: 'g1',
      fromMemberId: 'm2',
      toMemberId: 'm1',
      amountCents: 4000,
      currencyCode: 'VND',
      settledAt: testDate,
      createdAt: testDate,
    )));
    // g2: a single member and no "me". g3: two members and no "me".
    _right(await groups.createGroup(testGroup(id: 'g2')));
    _right(await members.addMember(testMember('solo', groupId: 'g2')));
    _right(await groups.createGroup(testGroup(id: 'g3')));
    _right(await members.addMember(testMember('x', groupId: 'g3')));
    _right(await members.addMember(testMember('y', groupId: 'g3')));
  });

  tearDown(() => database.close());

  /// The first batch to push: it stops at the first group boundary.
  Future<List<db.Activity>> firstBatch() async => [
        for (final (_, a) in await database.syncDao.nextBatch(1000)) a,
      ];

  Future<List<db.Activity>> allQueued() async =>
      database.select(database.activities).get();

  test('queues every local record with identical IDs and amounts (AC7)',
      () async {
    await uploader.upload('alice');

    final entries = await allQueued();
    expect(
      entries.map((a) => '${a.entityType} ${a.entityId}').toSet(),
      {
        'group g1', 'member m1', 'member m2', 'expense e1', 'settlement st1',
        'group g2', 'member solo', //
        'group g3', 'member x', 'member y',
      },
    );
    expect(entries.map((a) => a.action).toSet(), {'create'});
    expect(entries.map((a) => a.actorUid).toSet(), {'alice'});

    final expense = entries.firstWhere((a) => a.entityId == 'e1');
    final after = jsonDecode(expense.after) as Map<String, Object?>;
    expect(after['amountCents'], 10000);
    expect(
        (after['splits']! as List).single, containsPair('amountCents', 10000));
    expect(after['createdBy'], 'alice');
  });

  test('queues each group before its members, expenses and settlements',
      () async {
    await uploader.upload('alice');

    final g1 = (await firstBatch()).map((a) => a.entityId).toList();
    expect(g1, ['g1', 'm1', 'm2', 'e1', 'st1']);
  });

  test('links the account to the member marked as me, or the only member',
      () async {
    await uploader.upload('alice');

    Future<String?> link(String id) async =>
        (await database.memberDao.getMemberById(id))!.linkedUid;
    expect(await link('m1'), 'alice');
    expect(await link('m2'), isNull);
    expect(await link('solo'), 'alice');
    expect((await database.memberDao.getMemberById('solo'))!.isMe, isTrue);
    // Several members and no "me": the app asks later.
    expect(await link('x'), isNull);
    expect(await link('y'), isNull);
  });

  test('runs once per account, so reopening the app adds no duplicates (AC8)',
      () async {
    await uploader.upload('alice');
    final count = (await allQueued()).length;

    await uploader.upload('alice');

    expect(await allQueued(), hasLength(count));
    expect(await database.syncDao.pendingCount(), count);
  });
}
