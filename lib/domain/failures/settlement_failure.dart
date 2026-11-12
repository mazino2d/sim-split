import 'package:simsplit/domain/failures/core_failure.dart';

sealed class SettlementFailure extends Failure {
  const SettlementFailure(super.name);

  const factory SettlementFailure.notFound() = SettlementNotFound;
  const factory SettlementFailure.memberHasUnsettledDebts() =
      MemberHasUnsettledDebts;
  const factory SettlementFailure.amountExceedsDebt() = AmountExceedsDebt;
  const factory SettlementFailure.amountMustBePositive() =
      SettlementAmountMustBePositive;
  const factory SettlementFailure.sameMember() = SettlementSameMember;
  const factory SettlementFailure.memberNotInGroup() =
      SettlementMemberNotInGroup;
}

final class SettlementNotFound extends SettlementFailure {
  const SettlementNotFound() : super('settlement_not_found');
}

final class MemberHasUnsettledDebts extends SettlementFailure {
  const MemberHasUnsettledDebts() : super('member_has_unsettled_debts');
}

final class AmountExceedsDebt extends SettlementFailure {
  const AmountExceedsDebt() : super('amount_exceeds_debt');
}

final class SettlementAmountMustBePositive extends SettlementFailure {
  const SettlementAmountMustBePositive()
      : super('settlement_amount_must_be_positive');
}

/// Payer and payee of a settlement are the same member.
final class SettlementSameMember extends SettlementFailure {
  const SettlementSameMember() : super('settlement_same_member');
}

/// A member referenced by a settlement or debt is not part of the group.
final class SettlementMemberNotInGroup extends SettlementFailure {
  const SettlementMemberNotInGroup() : super('settlement_member_not_in_group');
}
