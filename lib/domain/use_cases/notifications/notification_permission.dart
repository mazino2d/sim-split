import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/notifications/notification_setup.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/notification_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// What the system allows and what the user chose on this install.
class GetNotificationSetup
    implements AsyncUseCase<NotificationSetup, NoParams> {
  const GetNotificationSetup({required NotificationRepository repository})
      : _repository = repository;

  final NotificationRepository _repository;

  @override
  Future<Either<Failure, NotificationSetup>> call(NoParams params) async =>
      right(await _repository.setup());
}

/// "Turn on": the system prompt, once the user asked for it (R-9 AC1). The
/// app never calls it on its own.
class RequestNotificationPermission
    implements AsyncUseCase<NotificationPermissionOutcome, NoParams> {
  const RequestNotificationPermission(
      {required NotificationRepository repository})
      : _repository = repository;

  final NotificationRepository _repository;

  @override
  Future<Either<Failure, NotificationPermissionOutcome>> call(
          NoParams params) async =>
      (await _repository.requestPermission()).map((permission) =>
          permission == NotificationPermission.granted
              ? NotificationPermissionOutcome.granted
              : NotificationPermissionOutcome.denied);
}

/// "Not now" on the one-time card: it never shows again (AC1, AC2).
class DismissNotificationPrompt
    implements AsyncUseCase<NotificationPermissionOutcome, NoParams> {
  const DismissNotificationPrompt({required NotificationRepository repository})
      : _repository = repository;

  final NotificationRepository _repository;

  @override
  Future<Either<Failure, NotificationPermissionOutcome>> call(
          NoParams params) async =>
      (await _repository.dismissPrompt())
          .map((_) => NotificationPermissionOutcome.notNow);
}
