import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

extension FailureStreamX<T> on Stream<Either<Failure, T>> {
  /// Converts errors thrown by the underlying stream (e.g. Drift query
  /// failures) into `Left(Failure.dbFailure(...))` data events so consumers
  /// always receive an [Either] instead of a stream error.
  Stream<Either<Failure, T>> mapErrorsToDbFailure() => transform(
        StreamTransformer<Either<Failure, T>, Either<Failure, T>>.fromHandlers(
          handleError: (error, stackTrace, sink) =>
              sink.add(left(Failure.dbFailure(error.toString()))),
        ),
      );
}
