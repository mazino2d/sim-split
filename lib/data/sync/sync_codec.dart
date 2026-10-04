import 'package:simsplit/data/database/app_database.dart' as db;

/// What a change was made to. The name is the value stored in activity
/// entries and the Firestore subcollection is derived from it.
enum SyncEntity {
  group,
  member,
  expense,
  settlement;

  /// Subcollection of `groups/{groupId}` that holds this entity; null for
  /// the group document itself.
  String? get collection => switch (this) {
        SyncEntity.group => null,
        SyncEntity.member => 'members',
        SyncEntity.expense => 'expenses',
        SyncEntity.settlement => 'settlements',
      };
}

enum SyncAction { create, update, delete }

/// Converts Drift rows into the JSON-safe maps that are stored in activity
/// entries and pushed to Firestore. Dates are epoch milliseconds and money
/// stays in integer cents. Local-only columns (`isMe`, the device-time
/// `updatedAt`) are left out: Firestore stamps `updatedAt` with server time.
class SyncCodec {
  const SyncCodec();

  /// Fields that change on every write and do not make it a change of its
  /// own.
  static const _bookkeeping = {'updatedBy'};

  Map<String, Object?> group(db.Group r) => {
        'id': r.id,
        'name': r.name,
        'emoji': r.emoji,
        'colorValue': r.colorValue,
        'currencyCode': r.currencyCode,
        'isArchived': r.isArchived,
        'createdAt': r.createdAt.millisecondsSinceEpoch,
        'createdBy': r.createdBy,
        'updatedBy': r.updatedBy,
        'deleted': r.deleted,
      };

  Map<String, Object?> member(db.Member r) => {
        'id': r.id,
        'name': r.name,
        'avatarColorValue': r.avatarColorValue,
        'emoji': r.emoji,
        'linkedUid': r.linkedUid,
        'createdAt': r.createdAt.millisecondsSinceEpoch,
        'createdBy': r.createdBy,
        'updatedBy': r.updatedBy,
        'deleted': r.deleted,
      };

  /// The expense with its splits embedded, so both always travel together
  /// (AC17, AC21).
  Map<String, Object?> expense(db.Expense r, List<db.ExpenseSplit> splits) => {
        'id': r.id,
        'title': r.title,
        'amountCents': r.amountCents,
        'currencyCode': r.currencyCode,
        'paidByMemberId': r.paidByMemberId,
        'splitType': r.splitType,
        'category': r.category,
        'note': r.note,
        'expenseDate': r.expenseDate.millisecondsSinceEpoch,
        'createdAt': r.createdAt.millisecondsSinceEpoch,
        'createdBy': r.createdBy,
        'updatedBy': r.updatedBy,
        'deleted': r.isDeleted,
        'splits': [
          for (final s in splits)
            {
              'id': s.id,
              'memberId': s.memberId,
              'value': s.value,
              'amountCents': s.amountCents,
            },
        ],
      };

  Map<String, Object?> settlement(db.Settlement r) => {
        'id': r.id,
        'fromMemberId': r.fromMemberId,
        'toMemberId': r.toMemberId,
        'amountCents': r.amountCents,
        'currencyCode': r.currencyCode,
        'note': r.note,
        'settledAt': r.settledAt.millisecondsSinceEpoch,
        'createdAt': r.createdAt.millisecondsSinceEpoch,
        'createdBy': r.createdBy,
        'updatedBy': r.updatedBy,
        'deleted': r.deleted,
      };

  /// Whether [a] and [b] describe the same record content.
  bool sameContent(Map<String, Object?> a, Map<String, Object?> b) {
    final keys = {...a.keys, ...b.keys}.difference(_bookkeeping);
    return keys.every((k) => _deepEquals(a[k], b[k]));
  }

  static bool _deepEquals(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      return a.keys.every((k) => b.containsKey(k) && _deepEquals(a[k], b[k]));
    }
    return a == b;
  }
}
