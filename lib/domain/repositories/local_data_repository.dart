import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';

/// The data kept on this device, as a whole.
abstract interface class LocalDataRepository {
  /// Removes everything on the device: groups with their members, expenses
  /// and settlements, the activity history, queued changes and sync state.
  Future<Either<Failure, Unit>> clearAll();
}
