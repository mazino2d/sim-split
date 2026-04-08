import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:simsplit/domain/entities/member.dart';

part 'debt.freezed.dart';

/// A computed (not stored) representation of a debt between two members.
@freezed
class Debt with _$Debt {
  const factory Debt({
    required Member from,
    required Member to,
    required int amountCents,
    required String currencyCode,
  }) = _Debt;
}

/// Per-member net balance within a group. Positive = owed to this member.
@freezed
class MemberBalance with _$MemberBalance {
  const factory MemberBalance({
    required Member member,

    /// Positive: others owe this member. Negative: this member owes others.
    required int netAmountCents,
  }) = _MemberBalance;
}

/// Complete debt summary for a group.
@freezed
class DebtSummary with _$DebtSummary {
  const factory DebtSummary({
    required String groupId,
    required String currencyCode,
    required List<MemberBalance> balances,

    /// Minimized list of transactions to settle all debts.
    required List<Debt> suggestions,
  }) = _DebtSummary;
}
