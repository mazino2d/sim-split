import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

part 'error_reports_notifier.g.dart';

/// Turns error reports on or off from the Diagnostics screen (R-4 AC26).
@riverpod
class ErrorReportsNotifier extends _$ErrorReportsNotifier {
  @override
  FutureOr<void> build() {}

  Future<Either<Failure, Unit>> setEnabled(bool enabled) async {
    state = const AsyncLoading();
    final result = await ref.read(setErrorReportsEnabledProvider)(enabled);
    if (ref.mounted) state = const AsyncData(null);
    return result;
  }
}
