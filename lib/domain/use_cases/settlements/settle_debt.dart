import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';
import 'package:simsplit/domain/failures/settlement_failure.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
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
  const SettleDebt({
    required SettlementRepository settlementRepository,
    required MemberRepository memberRepository,
  })  : _settlementRepository = settlementRepository,
        _memberRepository = memberRepository;

  final SettlementRepository _settlementRepository;
  final MemberRepository _memberRepository;

  @override
  Future<Either<Failure, Settlement>> call(SettleDebtParams params) async {
    if (params.amountCents <= 0) {
      return left(const SettlementFailure.amountMustBePositive());
    }
    if (params.fromMemberId == params.toMemberId) {
      return left(const SettlementFailure.sameMember());
    }

    for (final memberId in [params.fromMemberId, params.toMemberId]) {
      final memberResult = await _memberRepository.getMember(memberId);
      switch (memberResult) {
        case Left(value: MemberNotFound()):
          return left(const SettlementFailure.memberNotInGroup());
        case Left(value: final failure):
          return left(failure);
        case Right(value: final member) when member.groupId != params.groupId:
          return left(const SettlementFailure.memberNotInGroup());
        case Right():
          break;
      }
    }

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
