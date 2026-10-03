import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/settlements/delete_settlement.dart';
import 'package:simsplit/domain/use_cases/settlements/settle_debt.dart';

part 'settlement_notifier.g.dart';

/// Settlement mutations. Methods return the use case result directly;
/// [state] only reflects loading for UI (e.g. disabling Save).
@riverpod
class SettlementNotifier extends _$SettlementNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<Either<Failure, Settlement>> settleDebt({
    required String groupId,
    required String fromMemberId,
    required String toMemberId,
    required int amountCents,
    required String currencyCode,
    String? note,
    DateTime? settledAt,
  }) async {
    state = const AsyncLoading();
    final useCase = ref.read(settleDebtProvider);
    final result = await useCase(SettleDebtParams(
      groupId: groupId,
      fromMemberId: fromMemberId,
      toMemberId: toMemberId,
      amountCents: amountCents,
      currencyCode: currencyCode,
      note: note,
      settledAt: settledAt,
    ));
    if (ref.mounted) {
      state = result.fold(
        (failure) => AsyncError(failure, StackTrace.current),
        (_) => const AsyncData(null),
      );
    }
    return result;
  }

  Future<Either<Failure, Unit>> deleteSettlement(String id) async {
    state = const AsyncLoading();
    final useCase = ref.read(deleteSettlementProvider);
    final result = await useCase(DeleteSettlementParams(id: id));
    if (ref.mounted) {
      state = result.fold(
        (failure) => AsyncError(failure, StackTrace.current),
        (_) => const AsyncData(null),
      );
    }
    return result;
  }
}
