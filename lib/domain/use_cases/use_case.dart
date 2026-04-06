import 'package:fpdart/fpdart.dart';
import '../failures/core_failure.dart';

/// Synchronous use case.
abstract interface class UseCase<Type, Params> {
  Either<Failure, Type> call(Params params);
}

/// Asynchronous use case.
abstract interface class AsyncUseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

/// Streaming use case (for reactive UI).
abstract interface class StreamUseCase<Type, Params> {
  Stream<Either<Failure, Type>> call(Params params);
}

/// Sentinel for use cases that require no parameters.
class NoParams {
  const NoParams();
}
