import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/l10n/generated/app_localizations_en.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';
import 'package:simsplit/domain/failures/settlement_failure.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('failureMessage', () {
    test('maps known failures to localized messages', () {
      expect(
        failureMessage(const ExpenseFailure.exactDoesNotSumToTotal(), l10n),
        l10n.exactMustSumTotal,
      );
      expect(
        failureMessage(const GroupFailure.notFound(), l10n),
        l10n.errorGroupNotFound,
      );
      expect(
        failureMessage(const SettlementFailure.memberHasUnsettledDebts(), l10n),
        l10n.cannotRemoveMemberWithDebts,
      );
      expect(
        failureMessage(const Failure.dbFailure('boom'), l10n),
        l10n.errorDatabase,
      );
    });

    test('maps validation failures added to the domain layer', () {
      final cases = <Object, String>{
        const MemberFailure.hasHistory(): l10n.errorMemberHasHistory,
        const MemberFailure.nameEmpty(): l10n.errorMemberNameEmpty,
        const MemberFailure.notInGroup(): l10n.errorMemberNotInGroup,
        const MemberFailure.notFound(): l10n.errorMemberNotFound,
        const ExpenseFailure.titleEmpty(): l10n.errorExpenseTitleEmpty,
        const ExpenseFailure.duplicateParticipant():
            l10n.errorDuplicateParticipant,
        const ExpenseFailure.negativeSplitValue(): l10n.errorNegativeSplitValue,
        const ExpenseFailure.memberNotInGroup(): l10n.errorMemberNotInGroup,
        const SettlementFailure.sameMember(): l10n.errorSettlementSameMember,
        const SettlementFailure.amountMustBePositive():
            l10n.errorAmountMustBePositive,
        const SettlementFailure.memberNotInGroup(): l10n.errorMemberNotInGroup,
        const GroupFailure.currencyLocked(): l10n.currencyLockedHint,
      };
      cases.forEach((failure, message) {
        expect(failureMessage(failure, l10n), message, reason: '$failure');
      });
    });

    test('unwraps FailureException thrown by providers', () {
      expect(
        failureMessage(
          const FailureException(ExpenseFailure.notFound()),
          l10n,
        ),
        l10n.expenseNotFound,
      );
    });

    test('falls back to a generic message for unknown errors', () {
      expect(failureMessage(Exception('raw'), l10n), l10n.errorUnexpected);
      expect(failureMessage(null, l10n), l10n.errorUnexpected);
      expect(
        failureMessage(const Failure.unexpected('raw detail'), l10n),
        l10n.errorUnexpected,
      );
    });
  });
}
