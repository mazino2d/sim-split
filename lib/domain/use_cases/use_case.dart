import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

/// Synchronous use case.
abstract interface class UseCase<T, Params> {
  Either<Failure, T> call(Params params);
}

/// Asynchronous use case.
abstract interface class AsyncUseCase<T, Params> {
  Future<Either<Failure, T>> call(Params params);
}

/// Streaming use case (for reactive UI).
abstract interface class StreamUseCase<T, Params> {
  Stream<Either<Failure, T>> call(Params params);
}

/// Sentinel for use cases that require no parameters.
class NoParams {
  const NoParams();
}
