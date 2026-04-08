import 'package:simsplit/domain/failures/core_failure.dart';

sealed class SettlementFailure extends Failure {
  const SettlementFailure() : super();

  const factory SettlementFailure.notFound() = SettlementNotFound;
  const factory SettlementFailure.memberHasUnsettledDebts() =
      MemberHasUnsettledDebts;
  const factory SettlementFailure.amountExceedsDebt() = AmountExceedsDebt;
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
