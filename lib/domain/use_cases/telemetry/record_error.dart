import 'package:simsplit/domain/repositories/telemetry_repository.dart';

class RecordErrorParams {
  const RecordErrorParams(this.error, this.stack, {required this.shownToUser});

  final Object error;
  final StackTrace? stack;
  final bool shownToUser;
}

/// Reports an error (R-4 AC1, AC2). Fire-and-forget: it never fails.
class RecordError {
  const RecordError({required TelemetryRepository telemetryRepository})
      : _repository = telemetryRepository;

  final TelemetryRepository _repository;

  void call(RecordErrorParams params) => _repository
      .recordError(params.error, params.stack, shownToUser: params.shownToUser);
}
