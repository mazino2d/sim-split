import 'package:drift/drift.dart';
import 'connection/native_connection.dart'
    if (dart.library.html) 'connection/web_connection.dart';

import '../daos/expense_dao.dart';
import '../daos/expense_split_dao.dart';
import '../daos/group_dao.dart';
import '../daos/member_dao.dart';
import '../daos/settlement_dao.dart';
import '../models/expense_split_table.dart';
import '../models/expense_table.dart';
import '../models/group_table.dart';
import '../models/member_table.dart';
import '../models/settlement_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Groups, Members, Expenses, ExpenseSplits, Settlements],
  daos: [GroupDao, MemberDao, ExpenseDao, ExpenseSplitDao, SettlementDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Enable foreign key enforcement for SQLite
          await customStatement('PRAGMA foreign_keys = ON');
        },
        onUpgrade: (m, from, to) async {
          await customStatement('PRAGMA foreign_keys = ON');
          // Add future migration steps here as the schema evolves
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

QueryExecutor _openConnection() => openConnection();
