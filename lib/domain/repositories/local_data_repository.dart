import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/failures/core_failure.dart';

/// The data kept on this device, as a whole.
abstract interface class LocalDataRepository {
  /// Removes every group, member, expense and settlement on the device.
  Future<Either<Failure, Unit>> clearAll();
}
