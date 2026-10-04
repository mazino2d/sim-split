import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/data/database/app_database.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('a v2 database upgrades to v3 and keeps its data', () async {
    // The v2 schema as shipped in 1.0, with one group of each kind of row.
    final database = AppDatabase.forTesting(NativeDatabase.memory(
      setup: (raw) => raw
        ..execute(File('test/fixtures/schema_v2.sql').readAsStringSync())
        ..execute('''
        INSERT INTO groups VALUES ('g1', 'Trip', NULL, 0, 'VND', 0, 1, 1);
        INSERT INTO members VALUES ('m1', 'g1', 'An', 0, NULL, 1, 1);
        INSERT INTO expenses VALUES
          ('e1', 'g1', 'Dinner', 500000, 'VND', 'm1', 'equal', 'food', NULL,
           1, 1, 1, 0);
        INSERT INTO expense_splits VALUES ('s1', 'e1', 'm1', 500000, 500000);
        INSERT INTO settlements VALUES
          ('st1', 'g1', 'm1', 'm1', 100, 'VND', NULL, 1, 1);
        PRAGMA user_version = 2;
      '''),
    ));
    addTearDown(database.close);

    final group = (await database.groupDao.getGroupById('g1'))!;
    expect((group.name, group.deleted, group.createdBy), ('Trip', false, null));
    final member = (await database.memberDao.getMemberById('m1'))!;
    expect(
        (member.isMe, member.linkedUid, member.deleted), (true, null, false));
    final expense = (await database.expenseDao.getExpenseById('e1'))!;
    expect((expense.amountCents, expense.createdBy), (500000, null));
    final settlement = (await database.settlementDao.getSettlementById('st1'))!;
    expect(settlement.deleted, isFalse);

    expect(await database.syncDao.pendingCount(), 0);
    await database.syncDao.writeState('k', 'v');
    expect(await database.syncDao.readState('k'), 'v');
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      3,
    );
  });
}
