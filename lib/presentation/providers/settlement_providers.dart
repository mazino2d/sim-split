import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/di/injection.dart';
import '../../domain/entities/debt.dart';
import '../../domain/entities/settlement.dart';
import '../../domain/use_cases/settlements/calculate_debts.dart';
import '../../domain/use_cases/settlements/list_settlements.dart';

part 'settlement_providers.g.dart';

/// Computes and returns the current debt summary for a group.
@riverpod
Future<DebtSummary> debtSummary(Ref ref, String groupId, String currencyCode) {
  final useCase = ref.watch(calculateDebtsProvider);
  return useCase(
    CalculateDebtsParams(groupId: groupId, currencyCode: currencyCode),
  ).then(
    (either) => either.fold(
      (failure) => throw Exception(failure.toString()),
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
      (failure) => throw Exception(failure.toString()),
      (settlements) => settlements,
    ),
  );
}
