import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/repositories/telemetry_repository.dart';

/// Adds a step (a screen, an action) to the trail sent with the next error
/// report (R-4 AC3). Fire-and-forget.
class RecordBreadcrumb {
  const RecordBreadcrumb({required TelemetryRepository telemetryRepository})
      : _repository = telemetryRepository;

  final TelemetryRepository _repository;

  void call(BreadcrumbKind kind, String name) =>
      _repository.recordBreadcrumb(kind, name);
}
