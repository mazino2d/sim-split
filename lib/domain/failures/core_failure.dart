/// Base abstract class for all domain failures.
/// Use [Either<Failure, T>] from fpdart for error handling.
abstract class Failure {
  const Failure();

  const factory Failure.unexpected([String? message]) = UnexpectedFailure;
  const factory Failure.dbFailure([String? message]) = DbFailure;
}

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure([this.message]) : super();
  final String? message;
}

final class DbFailure extends Failure {
  const DbFailure([this.message]) : super();
  final String? message;
}
