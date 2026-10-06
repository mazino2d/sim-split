import 'package:freezed_annotation/freezed_annotation.dart';

part 'activity_entry.freezed.dart';

enum ActivityAction { create, update, delete, join }

enum ActivityEntityType { group, member, expense, settlement }

/// One change in a group's history (R-3, AC25–AC30): who changed which
/// record, how, and the record before and after, as synced snapshots
/// (dates in epoch milliseconds, money in integer cents).
@freezed
sealed class ActivityEntry with _$ActivityEntry {
  const factory ActivityEntry({
    required String id,
    required String groupId,
    required String actorUid,
    required ActivityAction action,
    required ActivityEntityType entityType,
    required String entityId,

    /// Null for a create or a join.
    Map<String, Object?>? before,
    @Default({}) Map<String, Object?> after,

    /// Device time of the change (AC29).
    required DateTime clientTime,

    /// Whether the change has reached the cloud.
    @Default(true) bool synced,
  }) = _ActivityEntry;
}
