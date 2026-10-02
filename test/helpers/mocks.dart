import 'package:fpdart/fpdart.dart' hide Group;
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/repositories/settlement_repository.dart';

class MockExpenseRepository extends Mock implements ExpenseRepository {}

class MockMemberRepository extends Mock implements MemberRepository {}

class MockGroupRepository extends Mock implements GroupRepository {}

class MockSettlementRepository extends Mock implements SettlementRepository {}

final testDate = DateTime(2024);

Member testMember(String id, {String groupId = 'g1', String? name}) => Member(
      id: id,
      groupId: groupId,
      name: name ?? 'Member $id',
      avatarColorValue: 0xFF000000,
      createdAt: testDate,
    );

Group testGroup({String id = 'g1', String currencyCode = 'VND'}) => Group(
      id: id,
      name: 'Group $id',
      colorValue: 0xFF000000,
      currencyCode: currencyCode,
      createdAt: testDate,
      updatedAt: testDate,
    );

Expense testExpense({
  String id = 'e1',
  String groupId = 'g1',
  String paidBy = 'm1',
  int amountCents = 10000,
  bool isDeleted = false,
  List<ExpenseSplit> splits = const [],
}) =>
    Expense(
      id: id,
      groupId: groupId,
      title: 'Expense $id',
      amountCents: amountCents,
      currencyCode: 'VND',
      paidByMemberId: paidBy,
      splitType: SplitType.equal,
      expenseDate: testDate,
      createdAt: testDate,
      updatedAt: testDate,
      isDeleted: isDeleted,
      splits: splits,
    );

/// Registers fallback values needed by `any()` matchers on entity params.
void registerEntityFallbacks() {
  registerFallbackValue(testExpense());
  registerFallbackValue(testMember('fallback'));
  registerFallbackValue(testGroup());
  registerFallbackValue(
    Settlement(
      id: 'fallback',
      groupId: 'g1',
      fromMemberId: 'a',
      toMemberId: 'b',
      amountCents: 1,
      currencyCode: 'VND',
      settledAt: testDate,
      createdAt: testDate,
    ),
  );
}

/// Extracts the failure from a Left, or fails the test on a Right.
Failure leftOf<T>(Either<Failure, T> result) => result.match(
      (failure) => failure,
      (value) => throw StateError('Expected Left but got Right($value)'),
    );
