
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/daos/expense_dao.dart';
import 'package:simsplit/data/daos/expense_split_dao.dart';
import 'package:simsplit/data/daos/group_dao.dart';
import 'package:simsplit/data/daos/member_dao.dart';
import 'package:simsplit/data/daos/settlement_dao.dart';
import 'package:simsplit/data/mappers/expense_mapper.dart';
import 'package:simsplit/data/mappers/group_mapper.dart';
import 'package:simsplit/data/mappers/member_mapper.dart';
import 'package:simsplit/data/mappers/settlement_mapper.dart';
import 'package:simsplit/data/repositories/drift_expense_repository.dart';
import 'package:simsplit/data/repositories/drift_group_repository.dart';
import 'package:simsplit/data/repositories/drift_member_repository.dart';
import 'package:simsplit/data/repositories/drift_settlement_repository.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/repositories/settlement_repository.dart';
import 'package:simsplit/domain/use_cases/expenses/add_expense.dart';
import 'package:simsplit/domain/use_cases/expenses/calculate_splits.dart';
import 'package:simsplit/domain/use_cases/expenses/delete_expense.dart';
import 'package:simsplit/domain/use_cases/expenses/edit_expense.dart';
import 'package:simsplit/domain/use_cases/expenses/list_expenses.dart';
import 'package:simsplit/domain/use_cases/groups/create_group.dart';
import 'package:simsplit/domain/use_cases/groups/delete_group.dart';
import 'package:simsplit/domain/use_cases/groups/get_group.dart';
import 'package:simsplit/domain/use_cases/groups/list_groups.dart';
import 'package:simsplit/domain/use_cases/groups/update_group.dart';
import 'package:simsplit/domain/use_cases/members/add_member.dart';
import 'package:simsplit/domain/use_cases/members/list_members.dart';
import 'package:simsplit/domain/use_cases/members/remove_member.dart';
import 'package:simsplit/domain/use_cases/members/update_member.dart';
import 'package:simsplit/domain/use_cases/settlements/calculate_debts.dart';
import 'package:simsplit/domain/use_cases/settlements/list_settlements.dart';
import 'package:simsplit/domain/use_cases/settlements/settle_debt.dart';

part 'injection.g.dart';

// ── Infrastructure ─────────────────────────────────────────────────────────

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) => AppDatabase();

// ── DAOs ───────────────────────────────────────────────────────────────────

@Riverpod(keepAlive: true)
GroupDao groupDao(Ref ref) => ref.watch(appDatabaseProvider).groupDao;

@Riverpod(keepAlive: true)
MemberDao memberDao(Ref ref) => ref.watch(appDatabaseProvider).memberDao;

@Riverpod(keepAlive: true)
ExpenseDao expenseDao(Ref ref) => ref.watch(appDatabaseProvider).expenseDao;

@Riverpod(keepAlive: true)
ExpenseSplitDao expenseSplitDao(Ref ref) =>
    ref.watch(appDatabaseProvider).expenseSplitDao;

@Riverpod(keepAlive: true)
SettlementDao settlementDao(Ref ref) =>
    ref.watch(appDatabaseProvider).settlementDao;

// ── Repositories (typed as Domain interfaces) ──────────────────────────────

@Riverpod(keepAlive: true)
GroupRepository groupRepository(Ref ref) => DriftGroupRepository(
      groupDao: ref.watch(groupDaoProvider),
      mapper: const GroupMapper(),
    );

@Riverpod(keepAlive: true)
MemberRepository memberRepository(Ref ref) => DriftMemberRepository(
      memberDao: ref.watch(memberDaoProvider),
      mapper: const MemberMapper(),
    );

@Riverpod(keepAlive: true)
ExpenseRepository expenseRepository(Ref ref) => DriftExpenseRepository(
      expenseDao: ref.watch(expenseDaoProvider),
      expenseSplitDao: ref.watch(expenseSplitDaoProvider),
      mapper: const ExpenseMapper(),
    );

@Riverpod(keepAlive: true)
SettlementRepository settlementRepository(Ref ref) => DriftSettlementRepository(
      settlementDao: ref.watch(settlementDaoProvider),
      mapper: const SettlementMapper(),
    );

// ── Use Cases ─────────────────────────────────────────────────────────────

@riverpod
ListGroups listGroups(Ref ref) =>
    ListGroups(groupRepository: ref.watch(groupRepositoryProvider));

@riverpod
GetGroup getGroup(Ref ref) =>
    GetGroup(groupRepository: ref.watch(groupRepositoryProvider));

@riverpod
CreateGroup createGroup(Ref ref) =>
    CreateGroup(groupRepository: ref.watch(groupRepositoryProvider));

@riverpod
UpdateGroup updateGroup(Ref ref) =>
    UpdateGroup(groupRepository: ref.watch(groupRepositoryProvider));

@riverpod
DeleteGroup deleteGroup(Ref ref) =>
    DeleteGroup(groupRepository: ref.watch(groupRepositoryProvider));

@riverpod
ListMembers listMembers(Ref ref) =>
    ListMembers(memberRepository: ref.watch(memberRepositoryProvider));

@riverpod
AddMember addMember(Ref ref) =>
    AddMember(memberRepository: ref.watch(memberRepositoryProvider));

@riverpod
RemoveMember removeMember(Ref ref) => RemoveMember(
      memberRepository: ref.watch(memberRepositoryProvider),
      expenseRepository: ref.watch(expenseRepositoryProvider),
    );

@riverpod
UpdateMember updateMember(Ref ref) =>
    UpdateMember(memberRepository: ref.watch(memberRepositoryProvider));

@riverpod
CalculateSplits calculateSplits(Ref ref) => const CalculateSplits();

@riverpod
ListExpenses listExpenses(Ref ref) =>
    ListExpenses(expenseRepository: ref.watch(expenseRepositoryProvider));

@riverpod
AddExpense addExpense(Ref ref) => AddExpense(
      expenseRepository: ref.watch(expenseRepositoryProvider),
      memberRepository: ref.watch(memberRepositoryProvider),
      calculateSplits: ref.watch(calculateSplitsProvider),
    );

@riverpod
EditExpense editExpense(Ref ref) => EditExpense(
      expenseRepository: ref.watch(expenseRepositoryProvider),
      calculateSplits: ref.watch(calculateSplitsProvider),
    );

@riverpod
DeleteExpense deleteExpense(Ref ref) =>
    DeleteExpense(expenseRepository: ref.watch(expenseRepositoryProvider));

@riverpod
CalculateDebts calculateDebts(Ref ref) => CalculateDebts(
      memberRepository: ref.watch(memberRepositoryProvider),
      expenseRepository: ref.watch(expenseRepositoryProvider),
      settlementRepository: ref.watch(settlementRepositoryProvider),
    );

@riverpod
SettleDebt settleDebt(Ref ref) =>
    SettleDebt(settlementRepository: ref.watch(settlementRepositoryProvider));

@riverpod
ListSettlements listSettlements(Ref ref) => ListSettlements(
    settlementRepository: ref.watch(settlementRepositoryProvider));
