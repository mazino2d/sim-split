import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
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
import 'package:simsplit/data/sync/sync_recorder.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';

import '../../../helpers/mocks.dart';

T _right<T>(Either<Failure, T> result) =>
    result.getOrElse((f) => throw StateError('Unexpected failure: $f'));

ExpenseSplit _split(String expenseId, String memberId, int cents) =>
    ExpenseSplit(
      id: '${expenseId}_$memberId',
      expenseId: expenseId,
      memberId: memberId,
      value: cents,
      amountCents: cents,
    );

Settlement _settlement() => Settlement(
      id: 's1',
      groupId: 'g1',
      fromMemberId: 'm2',
      toMemberId: 'm1',
      amountCents: 500,
      currencyCode: 'VND',
      settledAt: testDate,
      createdAt: testDate,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late db.AppDatabase database;
  late String? uid;
  late DriftGroupRepository groups;
  late DriftMemberRepository members;
  late DriftExpenseRepository expenses;
  late DriftSettlementRepository settlements;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    uid = 'alice';
    var nextId = 0;
    final recorder = SyncRecorder(
      syncDao: database.syncDao,
      currentUid: () => uid,
      clock: () => DateTime(2026, 10, 4, 12),
      newId: () => 'a${nextId++}',
    );
    groups = DriftGroupRepository(
      groupDao: database.groupDao,
      mapper: const GroupMapper(),
      recorder: recorder,
    );
    members = DriftMemberRepository(
      memberDao: database.memberDao,
      mapper: const MemberMapper(),
      recorder: recorder,
    );
    expenses = DriftExpenseRepository(
      expenseDao: database.expenseDao,
      expenseSplitDao: database.expenseSplitDao,
      mapper: const ExpenseMapper(),
      recorder: recorder,
    );
    settlements = DriftSettlementRepository(
      settlementDao: database.settlementDao,
      mapper: const SettlementMapper(),
      recorder: recorder,
    );
  });

  tearDown(() => database.close());

  /// Activity entries in outbox order.
  Future<List<db.Activity>> queued() async => [
        for (final (_, activity) in await database.syncDao.nextBatch(1000))
          activity,
      ];

  Map<String, Object?> decode(String json) =>
      jsonDecode(json) as Map<String, Object?>;

  Future<void> seedGroup() async {
    _right(await groups.createGroup(testGroup()));
    for (final id in ['m1', 'm2']) {
      _right(await members.addMember(testMember(id)));
    }
  }

  group('while signed in', () {
    test('every change is queued in order with who, when and the new state',
        () async {
      await seedGroup();
      _right(await expenses.addExpense(testExpense(
        splits: [_split('e1', 'm1', 6000), _split('e1', 'm2', 4000)],
      )));
      _right(await settlements.addSettlement(_settlement()));

      final entries = await queued();
      expect(
        entries.map((a) => '${a.action} ${a.entityType} ${a.entityId}'),
        [
          'create group g1',
          'create member m1',
          'create member m2',
          'create expense e1',
          'create settlement s1',
        ],
      );
      expect(entries.map((a) => a.actorUid).toSet(), {'alice'});
      expect(entries.first.clientTime, DateTime(2026, 10, 4, 12));

      final expense = decode(entries[3].after);
      expect(expense['amountCents'], 10000);
      expect(expense['createdBy'], 'alice');
      expect(
        (expense['splits']! as List).map((s) => (s as Map)['amountCents']),
        [6000, 4000],
      );
    });

    test('an edit records the state before and after', () async {
      await seedGroup();
      _right(await expenses.addExpense(testExpense(
        splits: [_split('e1', 'm1', 10000)],
      )));

      _right(await expenses.updateExpense(testExpense(
        amountCents: 8000,
        splits: [_split('e1', 'm2', 8000)],
      )));

      final edit = (await queued()).last;
      expect(edit.action, 'update');
      expect(decode(edit.before!)['amountCents'], 10000);
      expect(decode(edit.after)['amountCents'], 8000);
      expect(
        (decode(edit.after)['splits']! as List).single,
        containsPair('memberId', 'm2'),
      );
    });

    test('saving without changes records nothing', () async {
      await seedGroup();
      final count = (await queued()).length;

      _right(await groups.updateGroup(testGroup()));

      expect(await queued(), hasLength(count));
    });

    test('an edit keeps who created the record', () async {
      await seedGroup();
      uid = 'bob';

      _right(await groups.updateGroup(testGroup().copyWith(name: 'Trip')));

      final row = (await database.groupDao.getGroupById('g1'))!;
      expect(row.createdBy, 'alice');
      expect(row.updatedBy, 'bob');
    });

    test('a failed write records nothing', () async {
      await seedGroup();
      final count = (await queued()).length;

      final result = await expenses.addExpense(testExpense(
        splits: [_split('e1', 'ghost', 10000)],
      ));

      expect(result.isLeft(), isTrue);
      expect(await queued(), hasLength(count));
    });

    test('deletes are tombstones that are queued and hidden locally', () async {
      await seedGroup();
      _right(await expenses.addExpense(testExpense(
        splits: [_split('e1', 'm1', 10000)],
      )));
      _right(await settlements.addSettlement(_settlement()));
      _right(await members.addMember(testMember('m3')));

      _right(await expenses.deleteExpense('e1'));
      _right(await settlements.deleteSettlement('s1'));
      _right(await members.removeMember('m3'));
      _right(await groups.deleteGroup('g1'));

      final deletes = (await queued()).where((a) => a.action == 'delete');
      expect(deletes.map((a) => a.entityId), ['e1', 's1', 'm3', 'g1']);
      for (final entry in deletes) {
        expect(decode(entry.after)['deleted'], isTrue);
        expect(decode(entry.before!)['deleted'], isFalse);
      }

      expect(_right(await groups.watchGroups().first), isEmpty);
      expect(
        (await groups.getGroup('g1')).getLeft().toNullable(),
        isA<GroupNotFound>(),
      );
      expect(
        _right(await members.watchMembersByGroup('g1').first).map((m) => m.id),
        ['m1', 'm2'],
      );
      expect(
        (await members.getMember('m3')).getLeft().toNullable(),
        isA<MemberNotFound>(),
      );
      expect(_right(await settlements.watchSettlementsByGroup('g1').first),
          isEmpty);
      // The rows stay so the deletion can sync.
      expect(await database.groupDao.getGroupById('g1'), isNotNull);
    });
  });

  group('claiming "me"', () {
    test('marking a member as me links it to the account', () async {
      await seedGroup();

      _right(await members.updateMember(testMember('m1').copyWith(isMe: true)));

      final row = (await database.memberDao.getMemberById('m1'))!;
      expect(row.isMe, isTrue);
      expect(row.linkedUid, 'alice');
      expect(decode((await queued()).last.after)['linkedUid'], 'alice');
    });

    test('choosing another member releases the previous one', () async {
      await seedGroup();
      _right(await members.updateMember(testMember('m1').copyWith(isMe: true)));

      _right(await members.updateMember(testMember('m2').copyWith(isMe: true)));

      final m1 = (await database.memberDao.getMemberById('m1'))!;
      final m2 = (await database.memberDao.getMemberById('m2'))!;
      expect((m1.isMe, m1.linkedUid), (false, null));
      expect((m2.isMe, m2.linkedUid), (true, 'alice'));
      final last = (await queued()).reversed.take(2).toList();
      expect(last.map((a) => a.entityId), ['m2', 'm1']);
    });

    test("editing someone else's member keeps their claim", () async {
      await seedGroup();
      await (database.update(database.members)..where((m) => m.id.equals('m2')))
          .write(const db.MembersCompanion(linkedUid: Value('bob')));

      _right(await members.updateMember(testMember('m2', name: 'Bobby')));

      expect((await database.memberDao.getMemberById('m2'))!.linkedUid, 'bob');
    });
  });

  group('while signed out', () {
    test('changes are not queued and me stays local', () async {
      uid = null;
      await seedGroup();
      _right(await members.updateMember(testMember('m1').copyWith(isMe: true)));

      expect(await queued(), isEmpty);
      final row = (await database.memberDao.getMemberById('m1'))!;
      expect((row.isMe, row.linkedUid, row.createdBy), (true, null, null));
    });
  });
}
