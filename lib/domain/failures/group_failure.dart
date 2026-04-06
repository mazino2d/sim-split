import 'core_failure.dart';

sealed class GroupFailure extends Failure {
  const GroupFailure() : super();

  const factory GroupFailure.notFound() = GroupNotFound;
  const factory GroupFailure.nameTooShort() = GroupNameTooShort;
  const factory GroupFailure.nameTooLong() = GroupNameTooLong;
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
