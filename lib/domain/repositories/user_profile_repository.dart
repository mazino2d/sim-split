import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

/// The account's record in the cloud (R-4): name, email and the privacy
/// policy revision agreed to by signing in. Source of the warehouse's user
/// dimension; deleted with the account.
abstract interface class UserProfileRepository {
  /// Stores the agreement the first time this account signs in, on any
  /// device; later sign-ins leave it as it is (AC7).
  Future<Either<Failure, Unit>> recordAgreement(
      AuthUser user, String policyVersion);

  /// Deletes the signed-in account's record.
  Future<Either<Failure, Unit>> deleteProfile();
}
