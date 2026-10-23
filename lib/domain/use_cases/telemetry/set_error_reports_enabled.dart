import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/telemetry_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// The switch on the Diagnostics screen (R-4 AC25, AC26).
class SetErrorReportsEnabled implements AsyncUseCase<Unit, bool> {
  const SetErrorReportsEnabled(
      {required TelemetryRepository telemetryRepository})
      : _repository = telemetryRepository;

  final TelemetryRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(bool enabled) =>
      _repository.setErrorReportsEnabled(enabled);
}
