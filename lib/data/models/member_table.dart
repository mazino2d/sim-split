import 'package:drift/drift.dart';

import 'package:simsplit/data/models/group_table.dart';

class Members extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  IntColumn get avatarColorValue => integer()();
  TextColumn get emoji => text().nullable()();
  BoolColumn get isMe => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
