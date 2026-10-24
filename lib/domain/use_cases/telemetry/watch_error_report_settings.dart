import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/telemetry/error_report_settings.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/telemetry_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class WatchErrorReportSettings
    implements StreamUseCase<ErrorReportSettings, NoParams> {
  const WatchErrorReportSettings(
      {required TelemetryRepository telemetryRepository})
      : _repository = telemetryRepository;

  final TelemetryRepository _repository;

  @override
  Stream<Either<Failure, ErrorReportSettings>> call(NoParams params) =>
      _repository.watchErrorReportSettings();
}
