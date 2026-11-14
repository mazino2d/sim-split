import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide Group;
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/use_cases/expenses/delete_expense.dart';
import 'package:simsplit/domain/use_cases/groups/set_group_archived.dart';
import 'package:simsplit/domain/use_cases/groups/update_group.dart';
import 'package:simsplit/domain/use_cases/members/add_member.dart';
import 'package:simsplit/domain/use_cases/settlements/delete_settlement.dart';
import 'package:simsplit/domain/use_cases/settlements/settle_debt.dart';

import '../../../../helpers/mocks.dart';

// Archiving a group (#117): only the owner, and the group is read-only.

void main() {
  setUpAll(registerEntityFallbacks);

  group('SetGroupArchived', () {
    late MockGroupRepository groups;
    late MockAuthRepository auth;
    late SetGroupArchived useCase;

    void signedInAs(String uid) =>
        when(() => auth.watchCurrentUser()).thenAnswer(
            (_) => Stream.value(right<Failure, AuthUser?>(AuthUser(uid: uid))));

    void groupOwnedBy(String? owner, {bool archived = false}) =>
        when(() => groups.getGroup('g1')).thenAnswer((_) async =>
            right<Failure, Group>(
                testGroup().copyWith(ownerUid: owner, isArchived: archived)));

    setUp(() {
      groups = MockGroupRepository();
      auth = MockAuthRepository();
      useCase = SetGroupArchived(groupRepository: groups, authRepository: auth);
      when(() => groups.updateGroup(any())).thenAnswer((inv) async =>
          right<Failure, Group>(inv.positionalArguments.first as Group));
    });

    test('the owner archives and reopens', () async {
      signedInAs('alice');
      groupOwnedBy('alice');
      final archived = await useCase(
          const SetGroupArchivedParams(groupId: 'g1', archived: true));
      expect(archived.toNullable()!.isArchived, isTrue);

      groupOwnedBy('alice', archived: true);
      final reopened = await useCase(
          const SetGroupArchivedParams(groupId: 'g1', archived: false));
      expect(reopened.toNullable()!.isArchived, isFalse);
    });

    test('another member cannot', () async {
      signedInAs('bob');
      groupOwnedBy('alice');
      final result = await useCase(
          const SetGroupArchivedParams(groupId: 'g1', archived: true));
      expect(leftOf(result), isA<GroupNotOwner>());
      verifyNever(() => groups.updateGroup(any()));
    });

    test('a group not synced yet belongs to this device', () async {
      groupOwnedBy(null);
      final result = await useCase(
          const SetGroupArchivedParams(groupId: 'g1', archived: true));
      expect(result.isRight(), isTrue);
      verifyNever(() => auth.watchCurrentUser());
    });
  });

  group('an archived group is read-only', () {
    final archived = groupsWith(archived: true);

    test('no new member', () async {
      final members = MockMemberRepository();
      final result =
          await AddMember(memberRepository: members, groupRepository: archived)(
              const AddMemberParams(groupId: 'g1', name: 'Chi'));
      expect(leftOf(result), isA<GroupArchived>());
      verifyNever(() => members.addMember(any()));
    });

    test('no settlement recorded or deleted', () async {
      final settlements = MockSettlementRepository();
      final members = MockMemberRepository();
      final settled = await SettleDebt(
        settlementRepository: settlements,
        memberRepository: members,
        groupRepository: archived,
      )(const SettleDebtParams(
        groupId: 'g1',
        fromMemberId: 'm1',
        toMemberId: 'm2',
        amountCents: 100,
        currencyCode: 'VND',
      ));
      expect(leftOf(settled), isA<GroupArchived>());

      final deleted = await DeleteSettlement(
          settlementRepository: settlements,
          groupRepository:
              archived)(const DeleteSettlementParams(id: 's1', groupId: 'g1'));
      expect(leftOf(deleted), isA<GroupArchived>());
      verifyNever(() => settlements.deleteSettlement(any()));
    });

    test('no expense deleted', () async {
      final expenses = MockExpenseRepository();
      when(() => expenses.getExpense('e1'))
          .thenAnswer((_) async => right(testExpense()));
      final result = await DeleteExpense(
          expenseRepository: expenses,
          groupRepository: archived)(const DeleteExpenseParams(id: 'e1'));
      expect(leftOf(result), isA<GroupArchived>());
      verifyNever(() => expenses.deleteExpense(any()));
    });

    test('no change to the group itself', () async {
      final result = await UpdateGroup(
        groupRepository: archived,
        expenseRepository: MockExpenseRepository(),
      )(const UpdateGroupParams(id: 'g1', name: 'New', currencyCode: 'VND'));
      expect(leftOf(result), isA<GroupArchived>());
    });
  });
}
