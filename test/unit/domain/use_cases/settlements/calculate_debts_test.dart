import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/domain/failures/settlement_failure.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/repositories/settlement_repository.dart';
import 'package:simsplit/domain/use_cases/settlements/calculate_debts.dart';

class MockMemberRepository extends Mock implements MemberRepository {}

class MockExpenseRepository extends Mock implements ExpenseRepository {}

class MockSettlementRepository extends Mock implements SettlementRepository {}

Member _member(String id, String name) => Member(
      id: id,
      groupId: 'g1',
      name: name,
      avatarColorValue: 0xFF000000,
      createdAt: DateTime(2024),
    );

Expense _expense({
  required String id,
  required String paidBy,
  required int amountCents,
  required List<ExpenseSplit> splits,
}) =>
    Expense(
      id: id,
      groupId: 'g1',
      title: 'Expense $id',
      amountCents: amountCents,
      currencyCode: 'VND',
      paidByMemberId: paidBy,
      splitType: SplitType.equal,
      expenseDate: DateTime(2024),
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      splits: splits,
    );

ExpenseSplit _split(String expId, String memberId, int amountCents) =>
    ExpenseSplit(
      id: '${expId}_$memberId',
      expenseId: expId,
      memberId: memberId,
      value: amountCents,
      amountCents: amountCents,
    );

void main() {
  late MockMemberRepository members;
  late MockExpenseRepository expenses;
  late MockSettlementRepository settlements;
  late CalculateDebts useCase;

  final m1 = _member('m1', 'Alice');
  final m2 = _member('m2', 'Bob');
  final m3 = _member('m3', 'Charlie');

  setUp(() {
    members = MockMemberRepository();
    expenses = MockExpenseRepository();
    settlements = MockSettlementRepository();
    useCase = CalculateDebts(
      memberRepository: members,
      expenseRepository: expenses,
      settlementRepository: settlements,
    );
  });

  void stubMembers(List<Member> list) =>
      when(() => members.watchMembersByGroup(any()))
          .thenAnswer((_) => Stream.value(right(list)));

  void stubExpenses(List<Expense> list) =>
      when(() => expenses.watchExpensesByGroup(any()))
          .thenAnswer((_) => Stream.value(right(list)));

  void stubSettlements(List<Settlement> list) =>
      when(() => settlements.watchSettlementsByGroup(any()))
          .thenAnswer((_) => Stream.value(right(list)));

  test('simple A pays for all, B owes A', () async {
    stubMembers([m1, m2]);
    stubSettlements([]);
    // A paid 20000 for both; A owes 10000, B owes 10000
    stubExpenses([
      _expense(
        id: 'e1',
        paidBy: 'm1',
        amountCents: 20000,
        splits: [
          _split('e1', 'm1', 10000),
          _split('e1', 'm2', 10000),
        ],
      ),
    ]);

    final result = await useCase(const CalculateDebtsParams(
      groupId: 'g1',
      currencyCode: 'VND',
    ));

    final summary = result.getOrElse((_) => throw Exception());
    expect(summary.suggestions.length, 1);
    final debt = summary.suggestions.first;
    expect(debt.from.id, 'm2'); // Bob owes
    expect(debt.to.id, 'm1'); // Alice is owed
    expect(debt.amountCents, 10000);
  });

  test('chain: A→B→C simplifies to A→C', () async {
    stubMembers([m1, m2, m3]);
    stubSettlements([]);
    // Expense 1: B pays 10000 for A (A owes B 10000)
    // Expense 2: C pays 10000 for B (B owes C 10000)
    // Net: A owes 10000, B is neutral, C is owed 10000 → A pays C
    stubExpenses([
      _expense(
        id: 'e1',
        paidBy: 'm2',
        amountCents: 10000,
        splits: [_split('e1', 'm1', 10000)],
      ),
      _expense(
        id: 'e2',
        paidBy: 'm3',
        amountCents: 10000,
        splits: [_split('e2', 'm2', 10000)],
      ),
    ]);

    final result = await useCase(const CalculateDebtsParams(
      groupId: 'g1',
      currencyCode: 'VND',
    ));

    final summary = result.getOrElse((_) => throw Exception());
    expect(summary.suggestions.length, 1);
    expect(summary.suggestions.first.from.id, 'm1');
    expect(summary.suggestions.first.to.id, 'm3');
  });

  test('all settled → no suggestions', () async {
    stubMembers([m1, m2]);
    stubExpenses([
      _expense(
        id: 'e1',
        paidBy: 'm1',
        amountCents: 20000,
        splits: [
          _split('e1', 'm1', 10000),
          _split('e1', 'm2', 10000),
        ],
      ),
    ]);
    // B settles with A
    when(() => settlements.watchSettlementsByGroup(any()))
        .thenAnswer((_) => Stream.value(right([
              Settlement(
                id: 's1',
                groupId: 'g1',
                fromMemberId: 'm2',
                toMemberId: 'm1',
                amountCents: 10000,
                currencyCode: 'VND',
                settledAt: DateTime(2024),
                createdAt: DateTime(2024),
              ),
            ])));

    final result = await useCase(const CalculateDebtsParams(
      groupId: 'g1',
      currencyCode: 'VND',
    ));

    final summary = result.getOrElse((_) => throw Exception());
    expect(summary.suggestions.isEmpty, isTrue);
  });

  test('soft-deleted expenses are ignored', () async {
    stubMembers([m1, m2]);
    stubSettlements([]);
    // Only one active expense
    stubExpenses([
      _expense(
        id: 'e1',
        paidBy: 'm1',
        amountCents: 10000,
        splits: [_split('e1', 'm2', 10000)],
      ).copyWith(isDeleted: false),
      _expense(
        id: 'e2',
        paidBy: 'm2',
        amountCents: 50000,
        splits: [_split('e2', 'm1', 50000)],
      ).copyWith(isDeleted: true), // deleted — should not affect balances
    ]);

    final result = await useCase(const CalculateDebtsParams(
      groupId: 'g1',
      currencyCode: 'VND',
    ));

    final summary = result.getOrElse((_) => throw Exception());
    // Only e1 counts: B owes A 10000
    expect(summary.suggestions.length, 1);
    expect(summary.suggestions.first.from.id, 'm2');
    expect(summary.suggestions.first.amountCents, 10000);
  });

  Settlement settlement(String from, String to, int amountCents) => Settlement(
        id: 's_${from}_$to',
        groupId: 'g1',
        fromMemberId: from,
        toMemberId: to,
        amountCents: amountCents,
        currencyCode: 'VND',
        settledAt: DateTime(2024),
        createdAt: DateTime(2024),
      );

  const params = CalculateDebtsParams(groupId: 'g1', currencyCode: 'VND');

  test('4 members with tied balances settle fully in N-1 or fewer', () async {
    final m4 = _member('m4', 'Dave');
    stubMembers([m1, m2, m3, m4]);
    stubSettlements([]);
    // m1 and m2 each paid 20000 split equally across all four (5000 each):
    // m1 +10000, m2 +10000, m3 -10000, m4 -10000 (two ties).
    stubExpenses([
      for (final payer in ['m1', 'm2'])
        _expense(
          id: 'e_$payer',
          paidBy: payer,
          amountCents: 20000,
          splits: [
            for (final m in ['m1', 'm2', 'm3', 'm4'])
              _split('e_$payer', m, 5000),
          ],
        ),
    ]);

    final summary = (await useCase(params)).getOrElse((_) => throw Exception());

    expect(
      {for (final b in summary.balances) b.member.id: b.netAmountCents},
      {'m1': 10000, 'm2': 10000, 'm3': -10000, 'm4': -10000},
    );
    expect(summary.suggestions.length, lessThanOrEqualTo(3));
    // Ties are broken by member order: deterministic output.
    expect(
      summary.suggestions
          .map((d) => '${d.from.id}->${d.to.id}:${d.amountCents}'),
      ['m3->m1:10000', 'm4->m2:10000'],
    );

    // Applying the suggestions zeroes every balance.
    final remaining = {
      for (final b in summary.balances) b.member.id: b.netAmountCents,
    };
    for (final d in summary.suggestions) {
      remaining[d.from.id] = remaining[d.from.id]! + d.amountCents;
      remaining[d.to.id] = remaining[d.to.id]! - d.amountCents;
    }
    expect(remaining.values.every((v) => v == 0), isTrue);
  });

  test('unknown payer returns a failure instead of crashing', () async {
    stubMembers([m1, m2]);
    stubSettlements([]);
    stubExpenses([
      _expense(
        id: 'e1',
        paidBy: 'ghost',
        amountCents: 10000,
        splits: [_split('e1', 'm1', 10000)],
      ),
    ]);

    final result = await useCase(params);

    expect(result.getLeft().toNullable(), isA<SettlementMemberNotInGroup>());
  });

  test('unknown split member returns a failure instead of crashing', () async {
    stubMembers([m1, m2]);
    stubSettlements([]);
    stubExpenses([
      _expense(
        id: 'e1',
        paidBy: 'm1',
        amountCents: 10000,
        splits: [_split('e1', 'ghost', 10000)],
      ),
    ]);

    final result = await useCase(params);

    expect(result.getLeft().toNullable(), isA<SettlementMemberNotInGroup>());
  });

  test('unknown settlement member returns a failure instead of crashing',
      () async {
    stubMembers([m1, m2]);
    stubExpenses([]);
    stubSettlements([settlement('m1', 'ghost', 500)]);

    final result = await useCase(params);

    expect(result.getLeft().toNullable(), isA<SettlementMemberNotInGroup>());
  });

  test('partial settlement leaves the remaining debt', () async {
    stubMembers([m1, m2]);
    stubExpenses([
      _expense(
        id: 'e1',
        paidBy: 'm1',
        amountCents: 20000,
        splits: [_split('e1', 'm1', 10000), _split('e1', 'm2', 10000)],
      ),
    ]);
    stubSettlements([settlement('m2', 'm1', 4000)]);

    final summary = (await useCase(params)).getOrElse((_) => throw Exception());

    expect(summary.suggestions.length, 1);
    expect(summary.suggestions.single.from.id, 'm2');
    expect(summary.suggestions.single.to.id, 'm1');
    expect(summary.suggestions.single.amountCents, 6000);
  });
}
