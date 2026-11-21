import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/notifications/notification_open.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/notification_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// Registers this device with the signed-in account for push, in the app's
/// language (`en` or `vi`), once the user turned notifications on and the
/// system allows them. Does nothing otherwise.
class RegisterDevice implements AsyncUseCase<Unit, String> {
  const RegisterDevice({required NotificationRepository repository})
      : _repository = repository;

  final NotificationRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String locale) async {
    final setup = await _repository.setup();
    if (!setup.active) return right(unit);
    return _repository.registerDevice(locale);
  }
}

/// Emits when the push token changes.
class WatchTokenRefreshes implements StreamUseCase<Unit, NoParams> {
  const WatchTokenRefreshes({required NotificationRepository repository})
      : _repository = repository;

  final NotificationRepository _repository;

  @override
  Stream<Either<Failure, Unit>> call(NoParams params) =>
      _repository.tokenRefreshes().map(right);
}

/// The notifications the user taps: the one that launched the app first,
/// then those tapped while it runs (R-9 AC8).
class WatchNotificationOpens
    implements StreamUseCase<NotificationOpen, NoParams> {
  const WatchNotificationOpens({required NotificationRepository repository})
      : _repository = repository;

  final NotificationRepository _repository;

  @override
  Stream<Either<Failure, NotificationOpen>> call(NoParams params) async* {
    final initial = await _repository.initialOpen();
    if (initial != null) yield right(initial);
    yield* _repository.opens().map(right);
  }
}

/// Creates the Android channels, named in the app's language (AC5).
class SetUpNotificationChannels
    implements AsyncUseCase<Unit, List<NotificationChannelSpec>> {
  const SetUpNotificationChannels({required NotificationRepository repository})
      : _repository = repository;

  final NotificationRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(
      List<NotificationChannelSpec> channels) async {
    await _repository.setUpChannels(channels);
    return right(unit);
  }
}
