import 'package:simsplit/domain/repositories/telemetry_repository.dart';

/// Tells telemetry the app went to the background or came back (R-4 AC14).
class SetAppForeground {
  const SetAppForeground({required TelemetryRepository telemetryRepository})
      : _repository = telemetryRepository;

  final TelemetryRepository _repository;

  void call(bool foreground) => _repository.setForeground(foreground);
}
