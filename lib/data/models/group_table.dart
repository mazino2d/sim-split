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

  @override
  Set<Column> get primaryKey => {id};
}
