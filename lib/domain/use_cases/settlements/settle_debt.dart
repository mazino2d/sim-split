import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/settlement_repository.dart';
import 'package:simsplit/domain/value_objects/unique_id.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class SettleDebtParams {
  const SettleDebtParams({
    required this.groupId,
    required this.fromMemberId,
    required this.toMemberId,
    required this.amountCents,
    required this.currencyCode,
    this.note,
    this.settledAt,
  });

  final String groupId;
  final String fromMemberId;
  final String toMemberId;
  final int amountCents;
  final String currencyCode;
  final String? note;
  final DateTime? settledAt;
}

class SettleDebt implements AsyncUseCase<Settlement, SettleDebtParams> {
  const SettleDebt({required SettlementRepository settlementRepository})
      : _settlementRepository = settlementRepository;

  final SettlementRepository _settlementRepository;

  @override
  Future<Either<Failure, Settlement>> call(SettleDebtParams params) {
    final now = DateTime.now();
    final settlement = Settlement(
      id: UniqueId.generate().value,
      groupId: params.groupId,
      fromMemberId: params.fromMemberId,
      toMemberId: params.toMemberId,
      amountCents: params.amountCents,
      currencyCode: params.currencyCode,
      note: params.note?.trim(),
      settledAt: params.settledAt ?? now,
      createdAt: now,
    );
    return _settlementRepository.addSettlement(settlement);
  }
}
