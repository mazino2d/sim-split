import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/l10n/generated/app_localizations_en.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
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
