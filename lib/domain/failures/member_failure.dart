import 'package:simsplit/domain/failures/core_failure.dart';

sealed class MemberFailure extends Failure {
  const MemberFailure(super.name);

  const factory MemberFailure.notFound() = MemberNotFound;
  const factory MemberFailure.nameEmpty() = MemberNameEmpty;
  const factory MemberFailure.notInGroup() = MemberNotInGroup;
  const factory MemberFailure.hasHistory() = MemberHasHistory;
}

final class MemberNotFound extends MemberFailure {
  const MemberNotFound() : super('member_not_found');
}

/// The member name is empty or whitespace only.
final class MemberNameEmpty extends MemberFailure {
  const MemberNameEmpty() : super('member_name_empty');
}

/// The member does not belong to the requested group.
final class MemberNotInGroup extends MemberFailure {
  const MemberNotInGroup() : super('member_not_in_group');
}

/// The member is referenced by an expense (including soft-deleted ones),
/// an expense split, or a settlement, so it cannot be removed.
final class MemberHasHistory extends MemberFailure {
  const MemberHasHistory() : super('member_has_history');
}
