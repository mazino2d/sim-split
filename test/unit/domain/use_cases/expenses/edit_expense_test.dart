import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/use_cases/expenses/calculate_splits.dart';
import 'package:simsplit/domain/use_cases/expenses/edit_expense.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockExpenseRepository expenses;
  late MockMemberRepository members;
  late EditExpense useCase;

  setUpAll(registerEntityFallbacks);

  setUp(() {
    expenses = MockExpenseRepository();
    members = MockMemberRepository();
    useCase = EditExpense(
      expenseRepository: expenses,
      memberRepository: members,
      calculateSplits: const CalculateSplits(),
    );
    when(() => expenses.getExpense('e1'))
        .thenAnswer((_) async => right(testExpense()));
    when(() => members.watchMembersByGroup('g1')).thenAnswer(
      (_) => Stream.value(
        right<Failure, List<Member>>([testMember('m1'), testMember('m2')]),
      ),
    );
    when(() => expenses.updateExpense(any()))
        .thenAnswer((inv) async => right(inv.positionalArguments.first));
  });

  EditExpenseParams params({
    String title = 'Lunch',
    String paidBy = 'm2',
    List<String> participants = const ['m1', 'm2'],
  }) =>
      EditExpenseParams(
        id: 'e1',
        title: title,
        amountCents: 3001,
        currencyCode: 'VND',
        paidByMemberId: paidBy,
        splitType: SplitType.equal,
        splitInputs: [for (final m in participants) RawSplitInput(memberId: m)],
      );

  test('updates a valid expense', () async {
    final result = await useCase(params());

    final expense = result.getOrElse((f) => throw StateError('$f'));
    expect(expense.title, 'Lunch');
    expect(expense.paidByMemberId, 'm2');
    expect(expense.splits.fold(0, (s, e) => s + e.amountCents), 3001);
    verify(() => expenses.updateExpense(any())).called(1);
  });

  test('rejects blank title', () async {
    final result = await useCase(params(title: ''));

    expect(leftOf(result), isA<ExpenseTitleEmpty>());
    verifyNever(() => expenses.updateExpense(any()));
  });

  test('returns notFound for soft-deleted expense', () async {
    when(() => expenses.getExpense('e1'))
        .thenAnswer((_) async => right(testExpense(isDeleted: true)));

    final result = await useCase(params());

    expect(leftOf(result), isA<ExpenseNotFound>());
    verifyNever(() => expenses.updateExpense(any()));
  });

  test('propagates notFound from repository', () async {
    when(() => expenses.getExpense('e1')).thenAnswer(
      (_) async => left<Failure, Expense>(const ExpenseFailure.notFound()),
    );

    final result = await useCase(params());

    expect(leftOf(result), isA<ExpenseNotFound>());
  });

  test('rejects payer outside the expense group', () async {
    final result = await useCase(params(paidBy: 'outsider'));

    expect(leftOf(result), isA<ExpenseMemberNotInGroup>());
    verifyNever(() => expenses.updateExpense(any()));
  });

  test('rejects split participant outside the expense group', () async {
    final result = await useCase(params(participants: ['m1', 'outsider']));

    expect(leftOf(result), isA<ExpenseMemberNotInGroup>());
    verifyNever(() => expenses.updateExpense(any()));
  });
}
