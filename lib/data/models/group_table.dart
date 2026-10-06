import 'package:drift/drift.dart';

/// Drift table for groups.
/// Uses TEXT primary key (UUID) for portability.
class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get emoji => text().nullable()();
  IntColumn get colorValue => integer()();
  TextColumn get currencyCode => text().withDefault(const Constant('VND'))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Account uid that created / last changed the row (R-3). Null for rows
  /// written while signed out (v1 data, web).
  TextColumn get createdBy => text().nullable()();
  TextColumn get updatedBy => text().nullable()();

  /// Tombstone (R-3): deletions are soft so they can sync.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Server-owned sharing state, pulled from Firestore (R-3 P6): the owner,
  /// the accounts in the group (a JSON list of uids) and the current invite
  /// token. Never pushed.
  TextColumn get ownerUid => text().nullable()();
  TextColumn get memberUids => text().withDefault(const Constant('[]'))();
  TextColumn get inviteToken => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
