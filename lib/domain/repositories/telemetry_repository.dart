import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/telemetry/error_report_settings.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

/// Error reports (R-4): recorded on the device, scrubbed, queued and sent to
/// the telemetry endpoint in the background. Recording never fails or blocks
/// the caller (AC17).
abstract interface class TelemetryRepository {
  /// Records an error with the breadcrumbs that led to it. [shownToUser] is
  /// true for failures the app displayed (AC2), false for uncaught errors
  /// (AC1).
  void recordError(Object error, StackTrace? stack,
      {required bool shownToUser});

  /// Adds a step to the breadcrumb trail (the last 30 are kept).
  void recordBreadcrumb(BreadcrumbKind kind, String name);

  Stream<Either<Failure, ErrorReportSettings>> watchErrorReportSettings();

  /// Turning reports off deletes the waiting ones; turning them on again
  /// starts with a new report ID (AC26).
  Future<Either<Failure, Unit>> setErrorReportsEnabled(bool enabled);
}
