import 'package:simsplit/domain/failures/core_failure.dart';

sealed class SyncFailure extends Failure {
  const SyncFailure() : super();

  const factory SyncFailure.unsyncedChanges(int count) = SyncUnsyncedChanges;
  const factory SyncFailure.noConnection() = SyncNoConnection;
  const factory SyncFailure.serverError([String? message]) = SyncServerError;
}

/// Local changes have not reached the server yet, so signing out now would
/// lose them.
final class SyncUnsyncedChanges extends SyncFailure {
  const SyncUnsyncedChanges(this.count) : super();
  final int count;
}

/// The backend could not be reached.
final class SyncNoConnection extends SyncFailure {
  const SyncNoConnection() : super();
}

/// The backend rejected or failed the request.
final class SyncServerError extends SyncFailure {
  const SyncServerError([this.message]) : super();
  final String? message;
}
