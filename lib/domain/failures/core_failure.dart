/// Base abstract class for all domain failures.
/// Use [Either<Failure, T>] from fpdart for error handling.
abstract class Failure {
  const Failure(this.name);

  /// A stable snake_case name, e.g. `invite_invalid_link`, for telemetry.
  /// `runtimeType` can't be used: dart2js minifies it on web (#108).
  final String name;

  @override
  String toString() => name;

  const factory Failure.unexpected([String? message]) = UnexpectedFailure;
  const factory Failure.dbFailure([String? message]) = DbFailure;
}

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure([this.message]) : super('unexpected_failure');
  final String? message;
}

final class DbFailure extends Failure {
  const DbFailure([this.message]) : super('db_failure');
  final String? message;
}
