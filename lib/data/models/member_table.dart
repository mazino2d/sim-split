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

  /// The account that claimed this member (R-3). [isMe] stays a local
  /// column: it is true when this is the signed-in account's member.
  TextColumn get linkedUid => text().nullable()();

  /// Account uid that created / last changed the row (R-3). Null for rows
  /// written while signed out (v1 data, web).
  TextColumn get createdBy => text().nullable()();
  TextColumn get updatedBy => text().nullable()();

  /// Tombstone (R-3): deletions are soft so they can sync.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
