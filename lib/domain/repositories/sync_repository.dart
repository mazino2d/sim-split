import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

/// Keeps this device's groups in the signed-in account (R-3). Local data
/// stays the source of truth; changes are queued and pushed in order.
abstract interface class SyncRepository {
  /// Starts pushing local changes for [user] and pulling the account's
  /// groups in real time (AC15, AC18b). The first time [user] signs in on
  /// this device, every local group is queued for upload first (AC7).
  /// Queued changes survive restarts, so an interrupted upload resumes
  /// (AC8, AC16).
  Future<Either<Failure, Unit>> start(AuthUser user);

  /// Stops pushing and pulling. Queued changes stay queued.
  Future<Either<Failure, Unit>> stop();

  /// IDs of [groupId]'s records with changes not pushed yet, for the "not
  /// synced yet" mark (AC16).
  Stream<Either<Failure, Set<String>>> watchUnsyncedRecordIds(String groupId);

  /// Number of local changes not pushed yet.
  Future<Either<Failure, int>> pendingChangeCount();

  /// Removes the signed-in account from the cloud (AC6): leaves every group
  /// (its member stays, unclaimed) and deletes groups where it is the only
  /// member. Needs a connection.
  Future<Either<Failure, Unit>> deleteCloudData();
}
