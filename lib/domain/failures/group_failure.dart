import 'package:simsplit/domain/failures/core_failure.dart';

sealed class GroupFailure extends Failure {
  const GroupFailure(super.name);

  const factory GroupFailure.notFound() = GroupNotFound;
  const factory GroupFailure.nameTooShort() = GroupNameTooShort;
  const factory GroupFailure.nameTooLong() = GroupNameTooLong;
  const factory GroupFailure.currencyLocked() = GroupCurrencyLocked;
  const factory GroupFailure.collectorNotInGroup() = GroupCollectorNotInGroup;
  const factory GroupFailure.archived() = GroupArchived;
  const factory GroupFailure.notOwner() = GroupNotOwner;
}

final class GroupNotFound extends GroupFailure {
  const GroupNotFound() : super('group_not_found');
}

final class GroupNameTooShort extends GroupFailure {
  const GroupNameTooShort() : super('group_name_too_short');
}

final class GroupNameTooLong extends GroupFailure {
  const GroupNameTooLong() : super('group_name_too_long');
}

/// The group's currency cannot change once it has expenses.
final class GroupCurrencyLocked extends GroupFailure {
  const GroupCurrencyLocked() : super('group_currency_locked');
}

/// The member picked to collect settlements is not in the group (#116).
final class GroupCollectorNotInGroup extends GroupFailure {
  const GroupCollectorNotInGroup() : super('group_collector_not_in_group');
}

/// The group is archived and read-only until its owner reopens it (#117).
final class GroupArchived extends GroupFailure {
  const GroupArchived() : super('group_archived');
}

/// Only the group's owner can do this, e.g. archive or reopen it (#117).
final class GroupNotOwner extends GroupFailure {
  const GroupNotOwner() : super('group_not_owner');
}
