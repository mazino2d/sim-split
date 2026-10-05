import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/constants/auth_constants.dart';

import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/daos/expense_dao.dart';
import 'package:simsplit/data/daos/expense_split_dao.dart';
import 'package:simsplit/data/daos/group_dao.dart';
import 'package:simsplit/data/daos/member_dao.dart';
import 'package:simsplit/data/daos/settlement_dao.dart';
import 'package:simsplit/data/daos/sync_dao.dart';
import 'package:simsplit/data/mappers/expense_mapper.dart';
import 'package:simsplit/data/mappers/group_mapper.dart';
import 'package:simsplit/data/mappers/member_mapper.dart';
import 'package:simsplit/data/mappers/settlement_mapper.dart';
import 'package:simsplit/data/repositories/drift_expense_repository.dart';
import 'package:simsplit/data/repositories/drift_local_data_repository.dart';
import 'package:simsplit/data/repositories/firebase_auth_repository.dart';
import 'package:simsplit/data/repositories/firebase_web_auth_repository.dart';
import 'package:simsplit/data/repositories/drift_group_repository.dart';
import 'package:simsplit/data/repositories/drift_member_repository.dart';
import 'package:simsplit/data/repositories/drift_settlement_repository.dart';
import 'package:simsplit/data/repositories/firestore_sync_repository.dart';
import 'package:simsplit/data/sync/firestore_sync_pusher.dart';
import 'package:simsplit/data/sync/local_data_uploader.dart';
import 'package:simsplit/data/sync/sync_recorder.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/domain/repositories/local_data_repository.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/repositories/settlement_repository.dart';
import 'package:simsplit/domain/repositories/sync_repository.dart';
import 'package:simsplit/domain/use_cases/auth/delete_account.dart';
import 'package:simsplit/domain/use_cases/auth/sign_in_with_google.dart';
import 'package:simsplit/domain/use_cases/auth/sign_out.dart';
import 'package:simsplit/domain/use_cases/auth/watch_current_user.dart';
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
import 'package:simsplit/domain/use_cases/settlements/delete_settlement.dart';
import 'package:simsplit/domain/use_cases/settlements/list_settlements.dart';
import 'package:simsplit/domain/use_cases/settlements/settle_debt.dart';
import 'package:simsplit/domain/use_cases/sync/start_sync.dart';
import 'package:simsplit/domain/use_cases/sync/stop_sync.dart';

part 'injection.g.dart';

// ── Infrastructure ─────────────────────────────────────────────────────────

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) => AppDatabase();

/// Whether accounts are available: Firebase is initialised on Android, iOS
/// and web (see main.dart). On desktop the app stays local-only, with no
/// sign-in.
@Riverpod(keepAlive: true)
bool authAvailable(Ref ref) => Firebase.apps.isNotEmpty;

/// Only read when [authAvailable] is true. Configured in main.dart (no
/// offline cache; emulators in e2e).
@Riverpod(keepAlive: true)
FirebaseFirestore firestore(Ref ref) => FirebaseFirestore.instance;

/// Records local changes for sync while an account is signed in.
@Riverpod(keepAlive: true)
SyncRecorder syncRecorder(Ref ref) => SyncRecorder(
      syncDao: ref.watch(syncDaoProvider),
      currentUid: ref.watch(authAvailableProvider)
          ? () => FirebaseAuth.instance.currentUser?.uid
          : () => null,
    );

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

@Riverpod(keepAlive: true)
SyncDao syncDao(Ref ref) => ref.watch(appDatabaseProvider).syncDao;

// ── Repositories (typed as Domain interfaces) ──────────────────────────────

@Riverpod(keepAlive: true)
GroupRepository groupRepository(Ref ref) => DriftGroupRepository(
      groupDao: ref.watch(groupDaoProvider),
      mapper: const GroupMapper(),
      recorder: ref.watch(syncRecorderProvider),
    );

@Riverpod(keepAlive: true)
MemberRepository memberRepository(Ref ref) => DriftMemberRepository(
      memberDao: ref.watch(memberDaoProvider),
      mapper: const MemberMapper(),
      recorder: ref.watch(syncRecorderProvider),
    );

@Riverpod(keepAlive: true)
ExpenseRepository expenseRepository(Ref ref) => DriftExpenseRepository(
      expenseDao: ref.watch(expenseDaoProvider),
      expenseSplitDao: ref.watch(expenseSplitDaoProvider),
      mapper: const ExpenseMapper(),
      recorder: ref.watch(syncRecorderProvider),
    );

@Riverpod(keepAlive: true)
SettlementRepository settlementRepository(Ref ref) => DriftSettlementRepository(
      settlementDao: ref.watch(settlementDaoProvider),
      mapper: const SettlementMapper(),
      recorder: ref.watch(syncRecorderProvider),
    );

/// Only read when [authAvailable] is true.
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) => kIsWeb
    ? FirebaseWebAuthRepository(firebaseAuth: FirebaseAuth.instance)
    : FirebaseAuthRepository(
        firebaseAuth: FirebaseAuth.instance,
        googleSignIn: GoogleSignIn.instance,
        serverClientId: googleServerClientId,
      );

/// Only read when [authAvailable] is true.
@Riverpod(keepAlive: true)
SyncRepository syncRepository(Ref ref) {
  final database = ref.watch(appDatabaseProvider);
  final firestore = ref.watch(firestoreProvider);
  final pusher = FirestoreSyncPusher(
    syncDao: database.syncDao,
    firestore: firestore,
    log: (message) => debugPrint('[sync] $message'),
  );
  ref.onDispose(pusher.stop);
  return FirestoreSyncRepository(
    syncDao: database.syncDao,
    uploader: LocalDataUploader(database: database),
    pusher: pusher,
    firestore: firestore,
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
  );
}

@Riverpod(keepAlive: true)
LocalDataRepository localDataRepository(Ref ref) =>
    DriftLocalDataRepository(database: ref.watch(appDatabaseProvider));

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
UpdateGroup updateGroup(Ref ref) => UpdateGroup(
      groupRepository: ref.watch(groupRepositoryProvider),
      expenseRepository: ref.watch(expenseRepositoryProvider),
    );

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
RemoveMember removeMember(Ref ref) =>
    RemoveMember(memberRepository: ref.watch(memberRepositoryProvider));

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
      memberRepository: ref.watch(memberRepositoryProvider),
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
SettleDebt settleDebt(Ref ref) => SettleDebt(
      settlementRepository: ref.watch(settlementRepositoryProvider),
      memberRepository: ref.watch(memberRepositoryProvider),
    );

@riverpod
ListSettlements listSettlements(Ref ref) => ListSettlements(
    settlementRepository: ref.watch(settlementRepositoryProvider));

@riverpod
DeleteSettlement deleteSettlement(Ref ref) => DeleteSettlement(
    settlementRepository: ref.watch(settlementRepositoryProvider));

@riverpod
WatchCurrentUser watchCurrentUser(Ref ref) =>
    WatchCurrentUser(authRepository: ref.watch(authRepositoryProvider));

@riverpod
SignInWithGoogle signInWithGoogle(Ref ref) =>
    SignInWithGoogle(authRepository: ref.watch(authRepositoryProvider));

@riverpod
SignOut signOut(Ref ref) => SignOut(
      authRepository: ref.watch(authRepositoryProvider),
      localDataRepository: ref.watch(localDataRepositoryProvider),
      syncRepository: ref.watch(syncRepositoryProvider),
    );

@riverpod
DeleteAccount deleteAccount(Ref ref) => DeleteAccount(
      authRepository: ref.watch(authRepositoryProvider),
      localDataRepository: ref.watch(localDataRepositoryProvider),
      syncRepository: ref.watch(syncRepositoryProvider),
    );

@riverpod
StartSync startSync(Ref ref) =>
    StartSync(syncRepository: ref.watch(syncRepositoryProvider));

@riverpod
StopSync stopSync(Ref ref) =>
    StopSync(syncRepository: ref.watch(syncRepositoryProvider));
