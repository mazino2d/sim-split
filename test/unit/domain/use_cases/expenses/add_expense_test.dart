import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/use_cases/expenses/add_expense.dart';
import 'package:simsplit/domain/use_cases/expenses/calculate_splits.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockExpenseRepository expenses;
  late MockMemberRepository members;
  late AddExpense useCase;

  setUpAll(registerEntityFallbacks);

  setUp(() {
    expenses = MockExpenseRepository();
    members = MockMemberRepository();
    useCase = AddExpense(
      expenseRepository: expenses,
      memberRepository: members,
      calculateSplits: const CalculateSplits(),
    );
    when(() => members.watchMembersByGroup('g1')).thenAnswer(
      (_) => Stream.value(
        right<Failure, List<Member>>([testMember('m1'), testMember('m2')]),
      ),
    );
    when(() => expenses.addExpense(any()))
        .thenAnswer((inv) async => right(inv.positionalArguments.first));
  });

  AddExpenseParams params({
    String title = 'Dinner',
    int amountCents = 10000,
    String paidBy = 'm1',
    List<String> participants = const ['m1', 'm2'],
  }) =>
      AddExpenseParams(
        groupId: 'g1',
        title: title,
        amountCents: amountCents,
        currencyCode: 'VND',
        paidByMemberId: paidBy,
        splitType: SplitType.equal,
        splitInputs: [for (final m in participants) RawSplitInput(memberId: m)],
      );

  test('adds a valid expense with splits', () async {
    final result = await useCase(params());

    final expense = result.getOrElse((f) => throw StateError('$f'));
    expect(expense.groupId, 'g1');
    expect(expense.splits.map((s) => s.amountCents), [5000, 5000]);
    verify(() => expenses.addExpense(any())).called(1);
  });

  test('rejects blank title', () async {
    final result = await useCase(params(title: '   '));

    expect(leftOf(result), isA<ExpenseTitleEmpty>());
    verifyNever(() => expenses.addExpense(any()));
  });

  test('rejects non-positive amount', () async {
    final result = await useCase(params(amountCents: 0));

    expect(leftOf(result), isA<AmountMustBePositive>());
  });

  test('rejects payer outside the group', () async {
    final result = await useCase(params(paidBy: 'outsider'));

    expect(leftOf(result), isA<ExpenseMemberNotInGroup>());
    verifyNever(() => expenses.addExpense(any()));
  });

  test('rejects split participant outside the group', () async {
    final result = await useCase(params(participants: ['m1', 'outsider']));

    expect(leftOf(result), isA<ExpenseMemberNotInGroup>());
    verifyNever(() => expenses.addExpense(any()));
  });

  test('propagates member repository failure', () async {
    when(() => members.watchMembersByGroup('g1')).thenAnswer(
      (_) => Stream.value(
        left<Failure, List<Member>>(const Failure.dbFailure('boom')),
      ),
    );

    final result = await useCase(params());

    expect(leftOf(result), isA<DbFailure>());
  });

  test('rejects duplicate participants', () async {
    final result = await useCase(params(participants: ['m1', 'm1']));

    expect(leftOf(result), isA<DuplicateParticipant>());
    verifyNever(() => expenses.addExpense(any<Expense>()));
  });
}
