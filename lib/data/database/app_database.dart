import 'package:drift/drift.dart';
import 'package:simsplit/data/database/connection/native_connection.dart'
    if (dart.library.js_interop) 'connection/web_connection.dart';

import 'package:simsplit/data/daos/expense_dao.dart';
import 'package:simsplit/data/daos/expense_split_dao.dart';
import 'package:simsplit/data/daos/group_dao.dart';
import 'package:simsplit/data/daos/member_dao.dart';
import 'package:simsplit/data/daos/settlement_dao.dart';
import 'package:simsplit/data/daos/sync_dao.dart';
import 'package:simsplit/data/models/expense_split_table.dart';
import 'package:simsplit/data/models/expense_table.dart';
import 'package:simsplit/data/models/group_table.dart';
import 'package:simsplit/data/models/member_table.dart';
import 'package:simsplit/data/models/settlement_table.dart';
import 'package:simsplit/data/models/sync_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Groups,
    Members,
    Expenses,
    ExpenseSplits,
    Settlements,
    Activities,
    OutboxEntries,
    SyncStates,
  ],
  daos: [
    GroupDao,
    MemberDao,
    ExpenseDao,
    ExpenseSplitDao,
    SettlementDao,
    SyncDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Opens the database on a custom executor (e.g. an in-memory database in
  /// tests).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Enable foreign key enforcement for SQLite
          await customStatement('PRAGMA foreign_keys = ON');
        },
        onUpgrade: (m, from, to) async {
          await customStatement('PRAGMA foreign_keys = ON');
          if (from < 2) {
            await m.addColumn(members, members.emoji);
          }
          if (from < 3) {
            // R-3: audit columns, tombstones, claimed members and sync tables.
            await m.addColumn(groups, groups.createdBy);
            await m.addColumn(groups, groups.updatedBy);
            await m.addColumn(groups, groups.deleted);
            await m.addColumn(members, members.linkedUid);
            await m.addColumn(members, members.createdBy);
            await m.addColumn(members, members.updatedBy);
            await m.addColumn(members, members.deleted);
            await m.addColumn(expenses, expenses.createdBy);
            await m.addColumn(expenses, expenses.updatedBy);
            await m.addColumn(settlements, settlements.createdBy);
            await m.addColumn(settlements, settlements.updatedBy);
            await m.addColumn(settlements, settlements.deleted);
            await m.createTable(activities);
            await m.createTable(outboxEntries);
            await m.createTable(syncStates);
          }
          if (from < 4) {
            // R-3 P6: sharing state pulled from Firestore.
            await m.addColumn(groups, groups.ownerUid);
            await m.addColumn(groups, groups.memberUids);
            await m.addColumn(groups, groups.inviteToken);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

QueryExecutor _openConnection() => openConnection();
