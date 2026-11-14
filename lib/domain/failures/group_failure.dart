import 'package:simsplit/domain/failures/core_failure.dart';

sealed class GroupFailure extends Failure {
  const GroupFailure(super.name);

  const factory GroupFailure.notFound() = GroupNotFound;
  const factory GroupFailure.nameTooShort() = GroupNameTooShort;
  const factory GroupFailure.nameTooLong() = GroupNameTooLong;
  const factory GroupFailure.currencyLocked() = GroupCurrencyLocked;
  const factory GroupFailure.collectorNotInGroup() = GroupCollectorNotInGroup;
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
