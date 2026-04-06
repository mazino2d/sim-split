import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/di/injection.dart';
import '../../domain/use_cases/settlements/settle_debt.dart';

part 'settlement_notifier.g.dart';

@riverpod
class SettlementNotifier extends _$SettlementNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> settleDebt({
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

    return result.fold(
      (failure) {
        state = AsyncError(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncData(null);
        return true;
      },
    );
  }
}
