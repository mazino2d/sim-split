import 'package:drift/drift.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/sync/sync_codec.dart';
import 'package:simsplit/data/sync/sync_recorder.dart';

/// Queues every local group for upload the first time an account signs in
/// on this device (AC7).
///
/// Everything is queued in one Drift transaction, together with the marker
/// that says it was done, so the upload is queued exactly once. The queue
/// itself survives restarts and pushes are idempotent (same IDs), so an
/// interrupted upload resumes without duplicates (AC8).
class LocalDataUploader {
  const LocalDataUploader({
    required AppDatabase database,
    SyncCodec codec = const SyncCodec(),
    DateTime Function()? clock,
    String Function()? newId,
  })  : _db = database,
        _codec = codec,
        _clock = clock,
        _newId = newId;

  static const uploadedForKey = 'uploadedFor';

  final AppDatabase _db;
  final SyncCodec _codec;
  final DateTime Function()? _clock;
  final String Function()? _newId;

  Future<void> upload(String uid) => _db.transaction(() async {
        final sync = _db.syncDao;
        if (await sync.readState(uploadedForKey) == uid) return;
        final recorder = SyncRecorder(
          syncDao: sync,
          currentUid: () => uid,
          clock: _clock,
          newId: _newId,
        );

        final groups = await (_db.select(_db.groups)
              ..where((g) => g.deleted.equals(false))
              ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]))
            .get();
        for (final group in groups) {
          await _uploadGroup(group, uid, recorder);
        }
        await sync.writeState(uploadedForKey, uid);
      });

  Future<void> _uploadGroup(
      Group group, String uid, SyncRecorder recorder) async {
    await (_db.update(_db.groups)..where((g) => g.id.equals(group.id))).write(
      GroupsCompanion(
        createdBy: Value(group.createdBy ?? uid),
        updatedBy: Value(uid),
      ),
    );
    await recorder.record(
      groupId: group.id,
      entity: SyncEntity.group,
      entityId: group.id,
      action: SyncAction.create,
      after: _codec.group((await _db.groupDao.getGroupById(group.id))!),
    );

    // The account is the member marked as me, or the only member. Groups
    // with several members and no "me" ask later.
    final members = await _db.memberDao.getMembersByGroup(group.id);
    final mine = members.where((m) => m.isMe).firstOrNull ??
        (members.length == 1 ? members.single : null);
    for (final member in members) {
      final isMine = member.id == mine?.id;
      await (_db.update(_db.members)..where((m) => m.id.equals(member.id)))
          .write(MembersCompanion(
        isMe: Value(isMine),
        linkedUid: Value(isMine ? uid : null),
        createdBy: Value(member.createdBy ?? uid),
        updatedBy: Value(uid),
      ));
      await recorder.record(
        groupId: group.id,
        entity: SyncEntity.member,
        entityId: member.id,
        action: SyncAction.create,
        after: _codec.member((await _db.memberDao.getMemberById(member.id))!),
      );
    }

    final expenses = await (_db.select(_db.expenses)
          ..where((e) => e.groupId.equals(group.id) & e.isDeleted.equals(false))
          ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]))
        .get();
    for (final expense in expenses) {
      await (_db.update(_db.expenses)..where((e) => e.id.equals(expense.id)))
          .write(ExpensesCompanion(
        createdBy: Value(expense.createdBy ?? uid),
        updatedBy: Value(uid),
      ));
      await recorder.record(
        groupId: group.id,
        entity: SyncEntity.expense,
        entityId: expense.id,
        action: SyncAction.create,
        after: _codec.expense(
          (await _db.expenseDao.getExpenseById(expense.id))!,
          await _db.expenseSplitDao.getSplitsForExpense(expense.id),
        ),
      );
    }

    final settlements = await (_db.select(_db.settlements)
          ..where((s) => s.groupId.equals(group.id) & s.deleted.equals(false))
          ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
        .get();
    for (final settlement in settlements) {
      await (_db.update(_db.settlements)
            ..where((s) => s.id.equals(settlement.id)))
          .write(SettlementsCompanion(
        createdBy: Value(settlement.createdBy ?? uid),
        updatedBy: Value(uid),
      ));
      await recorder.record(
        groupId: group.id,
        entity: SyncEntity.settlement,
        entityId: settlement.id,
        action: SyncAction.create,
        after: _codec.settlement(
            (await _db.settlementDao.getSettlementById(settlement.id))!),
      );
    }
  }
}
