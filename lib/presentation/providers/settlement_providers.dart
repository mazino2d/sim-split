import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/domain/use_cases/settlements/calculate_debts.dart';
import 'package:simsplit/domain/use_cases/settlements/list_settlements.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';

part 'settlement_providers.g.dart';

/// Computes and returns the current debt summary for a group.
/// Re-computes automatically when expenses, settlements, or members change.
@riverpod
Future<DebtSummary> debtSummary(
    Ref ref, String groupId, String currencyCode) async {
  // Subscribe to reactive streams so this provider invalidates on any change.
  ref.watch(expenseListProvider(groupId));
  ref.watch(settlementListProvider(groupId));
  ref.watch(memberListProvider(groupId));
  // The settlement mode and collector are shared group settings (#116).
  final group = await ref.watch(liveGroupProvider(groupId).future);

  final useCase = ref.watch(calculateDebtsProvider);
  return useCase(
    CalculateDebtsParams(
      groupId: groupId,
      currencyCode: currencyCode,
      mode: group?.settlementMode ?? SettlementMode.simplified,
      hubMemberId: group?.settlementHubMemberId,
      ownerUid: group?.ownerUid,
    ),
  ).then(
    (either) => either.fold(
      (failure) => throw FailureException(failure),
      (summary) => summary,
    ),
  );
}

/// Reactive stream of settlement history for a group.
@riverpod
Stream<List<Settlement>> settlementList(Ref ref, String groupId) {
  final useCase = ref.watch(listSettlementsProvider);
  return useCase(ListSettlementsParams(groupId: groupId)).map(
    (either) => either.fold(
      (failure) => throw FailureException(failure),
      (settlements) => settlements,
    ),
  );
}
