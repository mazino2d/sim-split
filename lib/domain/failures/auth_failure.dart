import 'package:simsplit/domain/failures/core_failure.dart';

sealed class AuthFailure extends Failure {
  const AuthFailure(super.name);

  const factory AuthFailure.cancelled() = AuthCancelled;
  const factory AuthFailure.noConnection() = AuthNoConnection;
  const factory AuthFailure.signInFailed([String? message]) = AuthSignInFailed;
}

/// The user closed the provider's screen. Not an error worth showing.
final class AuthCancelled extends AuthFailure {
  const AuthCancelled() : super('auth_cancelled');
}

/// The provider or the backend could not be reached.
final class AuthNoConnection extends AuthFailure {
  const AuthNoConnection() : super('auth_no_connection');
}

/// Any other provider or backend error.
final class AuthSignInFailed extends AuthFailure {
  const AuthSignInFailed([this.message]) : super('auth_sign_in_failed');
  final String? message;
}
