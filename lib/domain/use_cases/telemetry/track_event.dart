import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/repositories/telemetry_repository.dart';

/// Records a screen, tap or operation (R-4 AC3, AC8). Fire-and-forget.
class TrackEvent {
  const TrackEvent({required TelemetryRepository telemetryRepository})
      : _repository = telemetryRepository;

  final TelemetryRepository _repository;

  void call(BreadcrumbKind kind, String name,
          {String? result, Duration? duration}) =>
      _repository.track(kind, name, result: result, duration: duration);
}
