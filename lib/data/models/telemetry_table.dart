import 'package:drift/drift.dart';

/// Error reports and usage events waiting to be sent to the telemetry
/// endpoint (R-4 AC13). Kept in Drift so they survive restarts and offline
/// periods; capped per kind, oldest dropped first.
class TelemetryQueue extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'error' | 'event'
  TextColumn get kind => text()();

  /// The JSON body item the endpoint expects (already scrubbed).
  TextColumn get payload => text()();

  DateTimeColumn get createdAt => dateTime()();
}
