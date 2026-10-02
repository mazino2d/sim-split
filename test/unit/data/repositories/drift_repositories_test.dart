import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide Group;
import 'package:simsplit/data/database/app_database.dart' show AppDatabase;
import 'package:simsplit/data/mappers/expense_mapper.dart';
import 'package:simsplit/data/mappers/group_mapper.dart';
import 'package:simsplit/data/mappers/member_mapper.dart';
import 'package:simsplit/data/mappers/settlement_mapper.dart';
import 'package:simsplit/data/repositories/drift_expense_repository.dart';
import 'package:simsplit/data/repositories/drift_group_repository.dart';
import 'package:simsplit/data/repositories/drift_member_repository.dart';
import 'package:simsplit/data/repositories/drift_settlement_repository.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';

import '../../../helpers/mocks.dart';

ExpenseSplit _split(String expenseId, String memberId, int cents) =>
    ExpenseSplit(
      id: '${expenseId}_$memberId',
      expenseId: expenseId,
      memberId: memberId,
      value: cents,
      amountCents: cents,
    );

T _right<T>(Either<Failure, T> result) =>
    result.getOrElse((f) => throw StateError('Unexpected failure: $f'));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftExpenseRepository expenses;
  late DriftMemberRepository members;
  late DriftSettlementRepository settlements;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expenses = DriftExpenseRepository(
      expenseDao: db.expenseDao,
      expenseSplitDao: db.expenseSplitDao,
      mapper: const ExpenseMapper(),
    );
    members = DriftMemberRepository(
      memberDao: db.memberDao,
      mapper: const MemberMapper(),
    );
    settlements = DriftSettlementRepository(
      settlementDao: db.settlementDao,
      mapper: const SettlementMapper(),
    );
    final groups = DriftGroupRepository(
      groupDao: db.groupDao,
      mapper: const GroupMapper(),
    );
    _right(await groups.createGroup(testGroup()));
    for (final id in ['m1', 'm2', 'm3']) {
      _right(await members.addMember(testMember(id)));
    }
  });

  tearDown(() => db.close());

  group('DriftExpenseRepository', () {
    test('addExpense stores expense and splits; getExpense hydrates them',
        () async {
      final expense = testExpense(
        amountCents: 10000,
        splits: [_split('e1', 'm1', 5000), _split('e1', 'm2', 5000)],
      );

      _right(await expenses.addExpense(expense));
      final stored = _right(await expenses.getExpense('e1'));

      expect(stored.amountCents, 10000);
      expect(stored.splits.map((s) => s.memberId), ['m1', 'm2']);
    });

    test('addExpense is atomic: a failing split rolls back the expense',
        () async {
      final expense = testExpense(
        splits: [
          _split('e1', 'm1', 5000),
          // FK violation: member does not exist.
          _split('e1', 'ghost', 5000),
        ],
      );

      final result = await expenses.addExpense(expense);

      expect(leftOf(result), isA<DbFailure>());
      expect(leftOf(await expenses.getExpense('e1')), isA<ExpenseNotFound>());
      expect(await db.expenseSplitDao.getSplitsForExpense('e1'), isEmpty);
    });

    test('updateExpense replaces splits atomically', () async {
      _right(await expenses.addExpense(testExpense(
        splits: [_split('e1', 'm1', 5000), _split('e1', 'm2', 5000)],
      )));

      // Invalid update: second split references a non-existent member.
      final bad = testExpense(
        amountCents: 9000,
        splits: [
          ExpenseSplit(
            id: 'new1',
            expenseId: 'e1',
            memberId: 'm3',
            value: 4500,
            amountCents: 4500,
          ),
          ExpenseSplit(
            id: 'new2',
            expenseId: 'e1',
            memberId: 'ghost',
            value: 4500,
            amountCents: 4500,
          ),
        ],
      );
      expect(leftOf(await expenses.updateExpense(bad)), isA<DbFailure>());

      // Original row and splits are untouched.
      final afterFailed = _right(await expenses.getExpense('e1'));
      expect(afterFailed.amountCents, 10000);
      expect(afterFailed.splits.map((s) => s.memberId), ['m1', 'm2']);

      // Valid update replaces everything.
      final good = testExpense(
        amountCents: 9000,
        splits: [_split('e1', 'm3', 9000)],
      );
      _right(await expenses.updateExpense(good));
      final afterGood = _right(await expenses.getExpense('e1'));
      expect(afterGood.amountCents, 9000);
      expect(afterGood.splits.map((s) => s.memberId), ['m3']);
    });

    test('updateExpense on missing expense returns notFound', () async {
      final result = await expenses.updateExpense(testExpense(id: 'missing'));

      expect(leftOf(result), isA<ExpenseNotFound>());
    });

    test('getExpense hides soft-deleted expenses', () async {
      _right(await expenses.addExpense(testExpense(
        splits: [_split('e1', 'm1', 10000)],
      )));
      _right(await expenses.deleteExpense('e1'));

      expect(leftOf(await expenses.getExpense('e1')), isA<ExpenseNotFound>());
    });

    test('watchExpensesByGroup emits expenses with their splits', () async {
      final emissions = <List<Expense>>[];
      final sub = expenses
          .watchExpensesByGroup('g1')
          .listen((event) => emissions.add(_right(event)));
      addTearDown(sub.cancel);

      await pumpEventQueue();
      expect(emissions.last, isEmpty);

      _right(await expenses.addExpense(testExpense(
        splits: [_split('e1', 'm1', 4000), _split('e1', 'm2', 6000)],
      )));
      await pumpEventQueue();

      // Every emission that contains the expense also contains its splits.
      final withExpense = emissions.where((e) => e.isNotEmpty).toList();
      expect(withExpense, isNotEmpty);
      for (final list in withExpense) {
        expect(list.single.splits.map((s) => s.amountCents), [4000, 6000]);
      }

      // Updating only the splits re-emits with fresh splits.
      _right(await expenses.updateExpense(testExpense(
        splits: [_split('e1', 'm3', 10000)],
      )));
      await pumpEventQueue();
      expect(emissions.last.single.splits.map((s) => s.memberId), ['m3']);

      // Soft-deleted expenses disappear from the stream.
      _right(await expenses.deleteExpense('e1'));
      await pumpEventQueue();
      expect(emissions.last, isEmpty);
    });
  });

  group('DriftMemberRepository', () {
    test('getMember returns MemberFailure.notFound for missing member',
        () async {
      expect(leftOf(await members.getMember('ghost')), isA<MemberNotFound>());
    });

    test('isMemberReferenced detects payer of soft-deleted expense', () async {
      _right(await expenses.addExpense(testExpense(
        paidBy: 'm1',
        splits: [_split('e1', 'm2', 10000)],
      )));
      _right(await expenses.deleteExpense('e1'));

      expect(_right(await members.isMemberReferenced('m1')), isTrue);
      expect(_right(await members.isMemberReferenced('m2')), isTrue);
      expect(_right(await members.isMemberReferenced('m3')), isFalse);
    });

    test('isMemberReferenced detects settlements', () async {
      _right(await settlements.addSettlement(Settlement(
        id: 's1',
        groupId: 'g1',
        fromMemberId: 'm2',
        toMemberId: 'm3',
        amountCents: 100,
        currencyCode: 'VND',
        settledAt: testDate,
        createdAt: testDate,
      )));

      expect(_right(await members.isMemberReferenced('m2')), isTrue);
      expect(_right(await members.isMemberReferenced('m3')), isTrue);
      expect(_right(await members.isMemberReferenced('m1')), isFalse);
    });

    test('removeMember on missing member returns notFound', () async {
      expect(
        leftOf(await members.removeMember('ghost')),
        isA<MemberNotFound>(),
      );
    });
  });
}
