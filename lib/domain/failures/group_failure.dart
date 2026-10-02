import 'package:simsplit/domain/failures/core_failure.dart';

sealed class GroupFailure extends Failure {
  const GroupFailure() : super();

  const factory GroupFailure.notFound() = GroupNotFound;
  const factory GroupFailure.nameTooShort() = GroupNameTooShort;
  const factory GroupFailure.nameTooLong() = GroupNameTooLong;
  const factory GroupFailure.currencyLocked() = GroupCurrencyLocked;
}

final class GroupNotFound extends GroupFailure {
  const GroupNotFound() : super();
}

final class GroupNameTooShort extends GroupFailure {
  const GroupNameTooShort() : super();
}

final class GroupNameTooLong extends GroupFailure {
  const GroupNameTooLong() : super();
}

/// The group's currency cannot change once it has expenses.
final class GroupCurrencyLocked extends GroupFailure {
  const GroupCurrencyLocked() : super();
}
