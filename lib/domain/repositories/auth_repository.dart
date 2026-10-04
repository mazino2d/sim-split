import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

abstract interface class AuthRepository {
  /// Emits the signed-in user, or `null` when signed out. The session is
  /// kept on the device, so this works offline after the first sign-in.
  Stream<Either<Failure, AuthUser?>> watchCurrentUser();

  Future<Either<Failure, AuthUser>> signInWithGoogle();

  Future<Either<Failure, Unit>> signOut();

  /// Deletes the account. May ask the user to confirm with the provider
  /// again when the last sign-in is not recent.
  Future<Either<Failure, Unit>> deleteAccount();
}
