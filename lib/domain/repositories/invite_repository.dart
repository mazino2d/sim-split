import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';

/// Sharing a group through invite links (R-3, AC9–AC14). Every call except
/// reading an existing link needs a connection.
abstract interface class InviteRepository {
  /// The group's invite link, created the first time it is shared (AC9).
  Future<Either<Failure, Uri>> inviteLink(String groupId);

  /// Replaces the group's link so old links stop working (AC13). Only the
  /// owner can.
  Future<Either<Failure, Uri>> resetInviteLink(String groupId);

  /// Joins the group that [token] invites to, as the signed-in account, and
  /// returns its ID (AC10). Joining a group twice is a no-op.
  Future<Either<Failure, String>> joinGroup(String token);

  /// Leaves the group (AC14): the account's member stays with its expenses
  /// and becomes unclaimed, and the group leaves this device.
  Future<Either<Failure, Unit>> leaveGroup(String groupId);
}
