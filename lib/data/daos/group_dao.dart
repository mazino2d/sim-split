import 'package:drift/drift.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/models/group_table.dart';

part 'group_dao.g.dart';

@DriftAccessor(tables: [Groups])
class GroupDao extends DatabaseAccessor<AppDatabase> with _$GroupDaoMixin {
  GroupDao(super.db);

  /// Streams groups that are not deleted, newest first.
  Stream<List<Group>> watchAllGroups() => (select(groups)
        ..where((g) => g.deleted.equals(false))
        ..orderBy([(g) => OrderingTerm.desc(g.createdAt)]))
      .watch();

  Future<Group?> getGroupById(String id) =>
      (select(groups)..where((g) => g.id.equals(id))).getSingleOrNull();

  Future<void> insertGroup(GroupsCompanion companion) =>
      into(groups).insert(companion);

  /// Writes only the columns present in [companion].
  Future<bool> updateGroupById(GroupsCompanion companion) async =>
      await (update(groups)..where((g) => g.id.equals(companion.id.value)))
          .write(companion) >
      0;

  /// Soft-delete: marks the group as a tombstone so the deletion can sync.
  Future<int> softDeleteGroup(String id, {String? updatedBy}) =>
      (update(groups)..where((g) => g.id.equals(id))).write(GroupsCompanion(
        deleted: const Value(true),
        updatedAt: Value(DateTime.now()),
        updatedBy: Value(updatedBy),
      ));
}
