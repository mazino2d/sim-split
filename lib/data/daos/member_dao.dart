import 'package:drift/drift.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/models/expense_split_table.dart';
import 'package:simsplit/data/models/expense_table.dart';
import 'package:simsplit/data/models/member_table.dart';
import 'package:simsplit/data/models/settlement_table.dart';

part 'member_dao.g.dart';

@DriftAccessor(tables: [Members, Expenses, ExpenseSplits, Settlements])
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

  /// Whether the member is referenced as payer of any expense (including
  /// soft-deleted ones), by any expense split, or by any settlement.
  Future<bool> isMemberReferenced(String memberId) async {
    final asPayer = await (selectOnly(expenses)
          ..addColumns([expenses.id])
          ..where(expenses.paidByMemberId.equals(memberId))
          ..limit(1))
        .getSingleOrNull();
    if (asPayer != null) return true;

    final inSplit = await (selectOnly(expenseSplits)
          ..addColumns([expenseSplits.id])
          ..where(expenseSplits.memberId.equals(memberId))
          ..limit(1))
        .getSingleOrNull();
    if (inSplit != null) return true;

    final inSettlement = await (selectOnly(settlements)
          ..addColumns([settlements.id])
          ..where(settlements.fromMemberId.equals(memberId) |
              settlements.toMemberId.equals(memberId))
          ..limit(1))
        .getSingleOrNull();
    return inSettlement != null;
  }
}
