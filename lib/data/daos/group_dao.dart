import 'package:drift/drift.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/models/group_table.dart';

part 'group_dao.g.dart';

@DriftAccessor(tables: [Groups])
class GroupDao extends DatabaseAccessor<AppDatabase> with _$GroupDaoMixin {
  GroupDao(super.db);

  Stream<List<Group>> watchAllGroups() =>
      (select(groups)..orderBy([(g) => OrderingTerm.desc(g.createdAt)]))
          .watch();

  Future<Group?> getGroupById(String id) =>
      (select(groups)..where((g) => g.id.equals(id))).getSingleOrNull();

  Future<void> insertGroup(GroupsCompanion companion) =>
      into(groups).insert(companion);

  Future<bool> updateGroupById(GroupsCompanion companion) =>
      update(groups).replace(companion);

  Future<int> deleteGroupById(String id) =>
      (delete(groups)..where((g) => g.id.equals(id))).go();
}
