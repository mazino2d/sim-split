import 'package:simsplit/domain/failures/core_failure.dart';

sealed class SyncFailure extends Failure {
  const SyncFailure(super.name);

  const factory SyncFailure.unsyncedChanges(int count) = SyncUnsyncedChanges;
  const factory SyncFailure.noConnection() = SyncNoConnection;
  const factory SyncFailure.serverError([String? message]) = SyncServerError;
}

/// Local changes have not reached the server yet, so signing out now would
/// lose them.
final class SyncUnsyncedChanges extends SyncFailure {
  const SyncUnsyncedChanges(this.count) : super('sync_unsynced_changes');
  final int count;
}

/// The backend could not be reached.
final class SyncNoConnection extends SyncFailure {
  const SyncNoConnection() : super('sync_no_connection');
}

/// The backend rejected or failed the request.
final class SyncServerError extends SyncFailure {
  const SyncServerError([this.message]) : super('sync_server_error');
  final String? message;
}
