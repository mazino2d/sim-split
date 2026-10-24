import 'package:fpdart/fpdart.dart' show Either, Unit;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

part 'auth_notifier.g.dart';

/// Account actions. Methods return the use case result directly; [state]
/// only reflects loading for UI (e.g. disabling a button). Navigation
/// follows the auth state through the router, not these results.
@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Runs a use case as a tracked operation (R-4 AC8).
  Future<Either<Failure, T>> _run<T>(
    TelemetryEvent event,
    Future<Either<Failure, T>> Function() action,
  ) async {
    state = const AsyncLoading();
    final result = await trackOp(ref.read(trackEventProvider), event, action);
    if (ref.mounted) {
      state = result.fold(
        (failure) => AsyncError(failure, StackTrace.current),
        (_) => const AsyncData(null),
      );
    }
    return result;
  }

  Future<Either<Failure, AuthUser>> signInWithGoogle() {
    final useCase = ref.read(signInWithGoogleProvider);
    return _run(
        TelemetryEvent.opSignInWithGoogle, () => useCase(const NoParams()));
  }

  Future<Either<Failure, Unit>> signOut() {
    final useCase = ref.read(signOutProvider);
    return _run(TelemetryEvent.opSignOut, () => useCase(const NoParams()));
  }

  Future<Either<Failure, Unit>> deleteAccount() {
    final useCase = ref.read(deleteAccountProvider);
    return _run(
        TelemetryEvent.opDeleteAccount, () => useCase(const NoParams()));
  }
}
