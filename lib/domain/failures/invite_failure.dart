import 'package:simsplit/domain/failures/core_failure.dart';

sealed class InviteFailure extends Failure {
  const InviteFailure() : super();

  const factory InviteFailure.invalidLink() = InviteInvalidLink;
}

/// The invite link is unknown or was reset by the group's owner (AC13).
final class InviteInvalidLink extends InviteFailure {
  const InviteInvalidLink() : super();
}
