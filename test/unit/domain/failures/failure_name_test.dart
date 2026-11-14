import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/failures/invite_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';
import 'package:simsplit/domain/failures/settlement_failure.dart';
import 'package:simsplit/domain/failures/sync_failure.dart';

/// Every concrete failure. The completeness test below fails when a new
/// one is added to `lib/domain/failures/` but not here.
const _all = <Failure>[
  Failure.unexpected(),
  Failure.dbFailure(),
  AuthFailure.cancelled(),
  AuthFailure.noConnection(),
  AuthFailure.signInFailed(),
  ExpenseFailure.notFound(),
  ExpenseFailure.memberNotFound(),
  ExpenseFailure.invalidSplitType(),
  ExpenseFailure.percentageDoesNotSumTo100(),
  ExpenseFailure.exactDoesNotSumToTotal(),
  ExpenseFailure.invalidShares(),
  ExpenseFailure.noParticipants(),
  ExpenseFailure.amountMustBePositive(),
  ExpenseFailure.memberNotInGroup(),
  ExpenseFailure.titleEmpty(),
  ExpenseFailure.titleTooLong(),
  ExpenseFailure.duplicateParticipant(),
  ExpenseFailure.negativeSplitValue(),
  GroupFailure.notFound(),
  GroupFailure.nameTooShort(),
  GroupFailure.nameTooLong(),
  GroupFailure.collectorNotInGroup(),
  GroupFailure.currencyLocked(),
  InviteFailure.invalidLink(),
  MemberFailure.notFound(),
  MemberFailure.nameEmpty(),
  MemberFailure.notInGroup(),
  MemberFailure.hasHistory(),
  SettlementFailure.notFound(),
  SettlementFailure.memberHasUnsettledDebts(),
  SettlementFailure.amountExceedsDebt(),
  SettlementFailure.amountMustBePositive(),
  SettlementFailure.sameMember(),
  SettlementFailure.memberNotInGroup(),
  SyncFailure.unsyncedChanges(1),
  SyncFailure.noConnection(),
  SyncFailure.serverError(),
];

/// The telemetry endpoint's `NAME` pattern (`services/telemetry/src/schema.ts`):
/// an op result that doesn't match rejects the whole batch (#108).
final _endpointName = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

String _snake(String type) => type
    .replaceAllMapped(RegExp('(?<=[a-z0-9])[A-Z]'), (m) => '_${m[0]}')
    .toLowerCase();

void main() {
  test('the list covers every failure class', () {
    final declared = Directory('lib/domain/failures')
        .listSync()
        .whereType<File>()
        .expand((f) => RegExp(r'^final class (\w+)', multiLine: true)
            .allMatches(f.readAsStringSync())
            .map((m) => m[1]!))
        .toSet();
    expect(_all.map((f) => f.runtimeType.toString()).toSet(), declared);
  });

  test('every failure name is accepted by the telemetry endpoint', () {
    for (final failure in _all) {
      expect(failure.name, matches(_endpointName), reason: '$failure');
    }
  });

  test('names are the snake_case class names, so data stays comparable', () {
    // runtimeType is readable here (the VM doesn't minify), not on web.
    for (final failure in _all) {
      expect(failure.name, _snake(failure.runtimeType.toString()));
    }
  });

  test('names are unique', () {
    final names = _all.map((f) => f.name).toList();
    expect(names.toSet().length, names.length);
  });

  test('toString is the stable name, not "Instance of …"', () {
    expect(const InviteFailure.invalidLink().toString(), 'invite_invalid_link');
  });
}
