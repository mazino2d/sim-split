import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide Group;
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/use_cases/groups/update_group.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockGroupRepository groups;
  late MockExpenseRepository expenses;
  late UpdateGroup useCase;

  setUpAll(registerEntityFallbacks);

  setUp(() {
    groups = MockGroupRepository();
    expenses = MockExpenseRepository();
    useCase = UpdateGroup(groupRepository: groups, expenseRepository: expenses);
    when(() => groups.getGroup('g1'))
        .thenAnswer((_) async => right(testGroup(currencyCode: 'VND')));
    when(() => groups.updateGroup(any()))
        .thenAnswer((inv) async => right(inv.positionalArguments.first));
  });

  void stubExpenses(List<Expense> list) =>
      when(() => expenses.watchExpensesByGroup('g1'))
          .thenAnswer((_) => Stream.value(right<Failure, List<Expense>>(list)));

  test('changes currency when group has no expenses', () async {
    stubExpenses([]);

    final result = await useCase(
      const UpdateGroupParams(id: 'g1', name: 'Trip', currencyCode: 'USD'),
    );

    expect(
      result.getOrElse((f) => throw StateError('$f')).currencyCode,
      'USD',
    );
  });

  test('rejects currency change when group has expenses', () async {
    stubExpenses([testExpense()]);

    final result = await useCase(
      const UpdateGroupParams(id: 'g1', name: 'Trip', currencyCode: 'USD'),
    );

    expect(leftOf(result), isA<GroupCurrencyLocked>());
    verifyNever(() => groups.updateGroup(any()));
  });

  test('allows other edits when group has expenses', () async {
    stubExpenses([testExpense()]);

    final result = await useCase(
      const UpdateGroupParams(id: 'g1', name: 'Renamed', currencyCode: 'VND'),
    );

    final group = result.getOrElse((f) => throw StateError('$f'));
    expect(group.name, 'Renamed');
    verifyNever(() => expenses.watchExpensesByGroup(any()));
  });

  test('rejects blank name', () async {
    final result = await useCase(
      const UpdateGroupParams(id: 'g1', name: '  ', currencyCode: 'VND'),
    );

    expect(leftOf(result), isA<GroupNameTooShort>());
  });

  test('propagates notFound', () async {
    when(() => groups.getGroup('g1')).thenAnswer(
      (_) async => left<Failure, Group>(const GroupFailure.notFound()),
    );

    final result = await useCase(
      const UpdateGroupParams(id: 'g1', name: 'Trip', currencyCode: 'USD'),
    );

    expect(leftOf(result), isA<GroupNotFound>());
  });
}
