import 'package:drift/drift.dart';
import 'package:simsplit/data/database/connection/native_connection.dart'
    if (dart.library.html) 'connection/web_connection.dart';

import 'package:simsplit/data/daos/expense_dao.dart';
import 'package:simsplit/data/daos/expense_split_dao.dart';
import 'package:simsplit/data/daos/group_dao.dart';
import 'package:simsplit/data/daos/member_dao.dart';
import 'package:simsplit/data/daos/settlement_dao.dart';
import 'package:simsplit/data/models/expense_split_table.dart';
import 'package:simsplit/data/models/expense_table.dart';
import 'package:simsplit/data/models/group_table.dart';
import 'package:simsplit/data/models/member_table.dart';
import 'package:simsplit/data/models/settlement_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Groups, Members, Expenses, ExpenseSplits, Settlements],
  daos: [GroupDao, MemberDao, ExpenseDao, ExpenseSplitDao, SettlementDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

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
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

QueryExecutor _openConnection() => openConnection();
