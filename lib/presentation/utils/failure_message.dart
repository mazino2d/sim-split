import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';
import 'package:simsplit/domain/failures/settlement_failure.dart';
import 'package:simsplit/domain/failures/sync_failure.dart';

/// Wraps a domain [Failure] so it can be thrown from reactive providers
/// (streams/futures) and later mapped back to a localized message.
class FailureException implements Exception {
  const FailureException(this.failure);

  final Failure failure;

  @override
  String toString() => 'FailureException(${failure.runtimeType})';
}

/// Maps any error surfaced to the UI (a [Failure], a [FailureException] or
/// an arbitrary object) to a user-facing localized message.
///
/// Unknown failure variants fall back to a generic message, so new domain
/// failures never leak raw `toString()` output to users.
String failureMessage(Object? error, AppLocalizations l10n) {
  final failure = switch (error) {
    FailureException(:final failure) => failure,
    Failure() => error,
    _ => null,
  };
  if (failure == null) return l10n.errorUnexpected;

  return switch (failure) {
    DbFailure() => l10n.errorDatabase,
    ExpenseNotFound() => l10n.expenseNotFound,
    ExpenseMemberNotFound() => l10n.errorMemberNotFound,
    InvalidSplitType() => l10n.errorInvalidSplitType,
    PercentageDoesNotSum() => l10n.percentageMustSum100,
    ExactDoesNotSum() => l10n.exactMustSumTotal,
    InvalidShares() => l10n.errorInvalidShares,
    NoParticipants() => l10n.errorNoParticipants,
    AmountMustBePositive() => l10n.errorAmountMustBePositive,
    GroupNotFound() => l10n.errorGroupNotFound,
    GroupNameTooShort() => l10n.errorGroupNameTooShort,
    GroupNameTooLong() => l10n.errorGroupNameTooLong,
    SettlementNotFound() => l10n.errorSettlementNotFound,
    MemberHasUnsettledDebts() => l10n.cannotRemoveMemberWithDebts,
    AmountExceedsDebt() => l10n.errorAmountExceedsDebt,
    SettlementAmountMustBePositive() => l10n.errorAmountMustBePositive,
    SettlementSameMember() => l10n.errorSettlementSameMember,
    SettlementMemberNotInGroup() => l10n.errorMemberNotInGroup,
    ExpenseMemberNotInGroup() => l10n.errorMemberNotInGroup,
    ExpenseTitleEmpty() => l10n.errorExpenseTitleEmpty,
    DuplicateParticipant() => l10n.errorDuplicateParticipant,
    NegativeSplitValue() => l10n.errorNegativeSplitValue,
    GroupCurrencyLocked() => l10n.currencyLockedHint,
    MemberNotFound() => l10n.errorMemberNotFound,
    MemberNameEmpty() => l10n.errorMemberNameEmpty,
    MemberNotInGroup() => l10n.errorMemberNotInGroup,
    MemberHasHistory() => l10n.errorMemberHasHistory,
    AuthNoConnection() => l10n.errorNoConnection,
    AuthCancelled() || AuthSignInFailed() => l10n.signInFailed,
    SyncUnsyncedChanges() => l10n.errorUnsyncedChanges,
    SyncNoConnection() => l10n.errorNoConnection,
    SyncServerError() => l10n.errorSyncFailed,
    // Wildcard keeps this compiling when new Failure variants are added.
    _ => l10n.errorUnexpected,
  };
}
