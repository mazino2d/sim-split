import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/telemetry/error_report_settings.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

/// Error reports and usage events (R-4): recorded on the device, queued and
/// sent to the telemetry endpoint in the background. Recording never fails
/// or blocks the caller (AC17).
abstract interface class TelemetryRepository {
  /// Records an error with the breadcrumbs that led to it. [shownToUser] is
  /// true for failures the app displayed (AC2), false for uncaught errors
  /// (AC1).
  void recordError(Object error, StackTrace? stack,
      {required bool shownToUser});

  /// Records a screen, tap or operation: a step in the breadcrumb trail
  /// (the last 30 are kept, while error reports are on) and, while an account
  /// is signed in, a usage event (AC8, AC9). Operations carry their [result]
  /// (`success` or the failure type) and duration.
  void track(BreadcrumbKind kind, String name,
      {String? result, Duration? duration});

  /// The app went to the background (flush usage events now, AC14) or came
  /// back (a new session after 30 minutes away).
  void setForeground(bool foreground);

  Stream<Either<Failure, ErrorReportSettings>> watchErrorReportSettings();

  /// Turning reports off deletes the waiting ones; turning them on again
  /// starts with a new report ID (AC26).
  Future<Either<Failure, Unit>> setErrorReportsEnabled(bool enabled);
}
