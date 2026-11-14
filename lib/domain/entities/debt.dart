import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';

part 'debt.freezed.dart';

/// A computed (not stored) representation of a debt between two members.
@freezed
sealed class Debt with _$Debt {
  const factory Debt({
    required Member from,
    required Member to,
    required int amountCents,
    required String currencyCode,
  }) = _Debt;
}

/// Per-member net balance within a group. Positive = owed to this member.
@freezed
sealed class MemberBalance with _$MemberBalance {
  const factory MemberBalance({
    required Member member,

    /// Positive: others owe this member. Negative: this member owes others.
    /// Always [paidCents] − [shareCents] + [settledCents].
    required int netAmountCents,

    /// What the member paid for the group's expenses (#110).
    @Default(0) int paidCents,

    /// The member's part of the expenses: what the trip cost them (#110).
    @Default(0) int shareCents,

    /// Recorded settlements: what they paid back minus what they were paid
    /// back.
    @Default(0) int settledCents,
  }) = _MemberBalance;
}

/// Complete debt summary for a group.
@freezed
sealed class DebtSummary with _$DebtSummary {
  const factory DebtSummary({
    required String groupId,
    required String currencyCode,
    required List<MemberBalance> balances,

    /// Transfers that settle every balance, worked out per [mode].
    required List<Debt> suggestions,
    @Default(SettlementMode.simplified) SettlementMode mode,

    /// Who everyone settles with in [SettlementMode.hub]. Null in hub mode
    /// means nobody could be picked automatically (the owner has no member
    /// in the group): [suggestions] is then empty until someone picks one.
    Member? collector,
  }) = _DebtSummary;
}
