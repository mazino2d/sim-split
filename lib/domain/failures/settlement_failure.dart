import 'package:simsplit/domain/failures/core_failure.dart';

sealed class SettlementFailure extends Failure {
  const SettlementFailure() : super();

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
  const SettlementNotFound() : super();
}

final class MemberHasUnsettledDebts extends SettlementFailure {
  const MemberHasUnsettledDebts() : super();
}

final class AmountExceedsDebt extends SettlementFailure {
  const AmountExceedsDebt() : super();
}

final class SettlementAmountMustBePositive extends SettlementFailure {
  const SettlementAmountMustBePositive() : super();
}

/// Payer and payee of a settlement are the same member.
final class SettlementSameMember extends SettlementFailure {
  const SettlementSameMember() : super();
}

/// A member referenced by a settlement or debt is not part of the group.
final class SettlementMemberNotInGroup extends SettlementFailure {
  const SettlementMemberNotInGroup() : super();
}
