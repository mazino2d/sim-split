import 'package:drift/drift.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/models/member_table.dart';

part 'member_dao.g.dart';

@DriftAccessor(tables: [Members])
class MemberDao extends DatabaseAccessor<AppDatabase> with _$MemberDaoMixin {
  MemberDao(super.db);

  Stream<List<Member>> watchMembersByGroup(String groupId) => (select(members)
        ..where((m) => m.groupId.equals(groupId))
        ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
      .watch();

  Future<Member?> getMemberById(String id) =>
      (select(members)..where((m) => m.id.equals(id))).getSingleOrNull();

  Future<void> insertMember(MembersCompanion companion) =>
      into(members).insert(companion);

  Future<bool> updateMemberById(MembersCompanion companion) =>
      update(members).replace(companion);

  Future<int> deleteMemberById(String id) =>
      (delete(members)..where((m) => m.id.equals(id))).go();

  Future<void> clearIsMeForGroup(String groupId) =>
      (update(members)..where((m) => m.groupId.equals(groupId)))
          .write(const MembersCompanion(isMe: Value(false)));
}
