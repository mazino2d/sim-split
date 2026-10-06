import 'package:intl/intl.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/activity_entry.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/utils/expense_category_ui.dart';

/// One field of a record in an activity entry: its value before and after
/// the change, either of which may be absent (AC26, AC27).
typedef ActivityField = ({String label, String? before, String? after});

/// Turns a group's activity entries into text (R-3 AC25–AC27, AC30).
///
/// Names come from the group's members, including removed ones whose names
/// only survive in the history.
class ActivityText {
  ActivityText({
    required List<ActivityEntry> entries,
    required List<Member> members,
    required this.l10n,
    required this.locale,
    required this.currencyCode,
  }) {
    for (final entry in entries.reversed) {
      if (entry.entityType != ActivityEntityType.member) continue;
      final name = (entry.after['name'] ?? entry.before?['name']) as String?;
      if (name != null) _memberNames[entry.entityId] = name;
    }
    for (final member in members) {
      _memberNames[member.id] = member.name;
      if (member.linkedUid case final uid?) {
        _accountNames[uid] =
            member.isMe ? '${member.name} ${l10n.meLabel}' : member.name;
      }
    }
  }

  final AppLocalizations l10n;
  final String locale;
  final String currencyCode;
  final _memberNames = <String, String>{};
  final _accountNames = <String, String>{};

  /// Keys that are bookkeeping, not content.
  static const _hidden = {
    'id',
    'createdAt',
    'createdBy',
    'updatedBy',
    'editedAt',
    'deleted',
    'avatarColorValue',
    'colorValue',
    'isArchived',
    'currencyCode',
  };

  String actor(ActivityEntry entry) =>
      _accountNames[entry.actorUid] ?? l10n.someone;

  String member(Object? id) => _memberNames[id] ?? '?';

  /// "Member added / edited / deleted item" (AC25).
  String summary(ActivityEntry entry) {
    final who = actor(entry);
    if (entry.action == ActivityAction.join) return l10n.activityJoined(who);
    if (entry.entityType == ActivityEntityType.group &&
        entry.action == ActivityAction.create) {
      return l10n.activityCreatedGroup(who);
    }
    // Claiming a name, or releasing it on leaving (AC30).
    if (entry.entityType == ActivityEntityType.member &&
        entry.action == ActivityAction.update) {
      final before = entry.before?['linkedUid'];
      final after = entry.after['linkedUid'];
      if (before == null && after == entry.actorUid) {
        return l10n.activityClaimed(who, member(entry.entityId));
      }
      if (before == entry.actorUid && after == null) {
        return l10n.activityLeft(who);
      }
    }
    final item = _item(entry);
    return switch (entry.action) {
      ActivityAction.create => l10n.activityAdded(who, item),
      ActivityAction.update => l10n.activityEdited(who, item),
      ActivityAction.delete => l10n.activityDeleted(who, item),
      ActivityAction.join => l10n.activityJoined(who),
    };
  }

  String _item(ActivityEntry entry) {
    final record = entry.action == ActivityAction.delete
        ? (entry.before ?? entry.after)
        : entry.after;
    return switch (entry.entityType) {
      ActivityEntityType.expense => '“${record['title'] ?? '?'}”',
      ActivityEntityType.settlement => l10n.activityItemPayment(
          member(record['fromMemberId']), member(record['toMemberId'])),
      ActivityEntityType.member => l10n.activityItemMember(
          record['name'] as String? ?? member(entry.entityId)),
      ActivityEntityType.group => l10n.activityItemGroup,
    };
  }

  /// The fields to show for [entry]: what changed for an edit (AC26), the
  /// whole record when deleted (AC27) or added.
  List<ActivityField> fields(ActivityEntry entry) {
    final before = entry.before;
    switch (entry.action) {
      case ActivityAction.join:
        return const [];
      case ActivityAction.create:
        return _rows(entry, null, entry.after);
      case ActivityAction.delete:
        return _rows(entry, null, before ?? entry.after);
      case ActivityAction.update:
        return [
          for (final row in _rows(entry, before, entry.after))
            if (row.before != row.after) row,
        ];
    }
  }

  List<ActivityField> _rows(
    ActivityEntry entry,
    Map<String, Object?>? before,
    Map<String, Object?> after,
  ) {
    final currency =
        (after['currencyCode'] ?? before?['currencyCode']) as String? ??
            currencyCode;
    final keys = {...?before?.keys, ...after.keys}.difference(_hidden);
    final rows = <ActivityField>[];
    for (final key in _ordered(keys)) {
      if (key == 'splits') {
        rows.addAll(_splitRows(before?['splits'], after['splits'], currency,
            showBefore: before != null));
        continue;
      }
      String? show(Map<String, Object?>? record) =>
          record == null || !record.containsKey(key)
              ? null
              : _value(entry.entityType, key, record[key], currency);
      rows.add((
        label: _label(entry.entityType, key),
        before: before == null ? null : show(before),
        after: show(after),
      ));
    }
    return rows;
  }

  /// Each member's share of an expense, by name.
  List<ActivityField> _splitRows(
    Object? before,
    Object? after,
    String currency, {
    required bool showBefore,
  }) {
    Map<String, int> shares(Object? splits) => {
          for (final s in (splits as List? ?? const []).cast<Map>())
            s['memberId'] as String: s['amountCents'] as int,
        };
    final old = shares(before);
    final now = shares(after);
    return [
      for (final id in {...old.keys, ...now.keys})
        (
          label: l10n.fieldShare(member(id)),
          before: !showBefore
              ? null
              : old[id] == null
                  ? '—'
                  : formatMoney(old[id]!, currency),
          after: now[id] == null ? '—' : formatMoney(now[id]!, currency),
        ),
    ];
  }

  static const _order = [
    'name',
    'title',
    'amountCents',
    'paidByMemberId',
    'fromMemberId',
    'toMemberId',
    'expenseDate',
    'settledAt',
    'category',
    'splitType',
    'splits',
    'note',
    'emoji',
    'linkedUid',
  ];

  static List<String> _ordered(Set<String> keys) => [
        ..._order.where(keys.contains),
        ...keys.where((k) => !_order.contains(k)),
      ];

  String _label(ActivityEntityType type, String key) => switch (key) {
        'name' =>
          type == ActivityEntityType.group ? l10n.groupName : l10n.fieldName,
        'title' => l10n.expenseTitle,
        'amountCents' => l10n.amount,
        'paidByMemberId' => l10n.paidBy,
        'fromMemberId' => l10n.fieldFrom,
        'toMemberId' => l10n.fieldTo,
        'expenseDate' || 'settledAt' => l10n.date,
        'category' => l10n.category,
        'splitType' => l10n.splitType,
        'note' => l10n.fieldNote,
        'emoji' => l10n.fieldEmoji,
        'linkedUid' => l10n.fieldClaimed,
        _ => key,
      };

  String _value(
      ActivityEntityType type, String key, Object? value, String currency) {
    if (key == 'linkedUid') return value == null ? l10n.valueNo : l10n.valueYes;
    if (value == null || value == '') return '—';
    return switch (key) {
      'amountCents' => formatMoney(value as int, currency),
      'paidByMemberId' || 'fromMemberId' || 'toMemberId' => member(value),
      'expenseDate' || 'settledAt' => DateFormat('d MMM yyyy', locale)
          .format(DateTime.fromMillisecondsSinceEpoch(value as int)),
      'category' =>
        (ExpenseCategory.values.asNameMap()[value] ?? ExpenseCategory.other)
            .label(l10n),
      'splitType' => switch (value) {
          'equal' => l10n.splitEqual,
          'percentage' => l10n.splitPercentage,
          'exact' => l10n.splitExact,
          'shares' => l10n.splitShares,
          _ => '$value',
        },
      _ => '$value',
    };
  }
}
