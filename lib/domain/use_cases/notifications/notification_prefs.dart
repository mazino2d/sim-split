import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/notification_failure.dart';
import 'package:simsplit/domain/repositories/notification_prefs_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// The account's notification choices (R-9 AC3, AC4).
class WatchNotificationPrefs
    implements StreamUseCase<NotificationPrefs, NoParams> {
  const WatchNotificationPrefs(
      {required NotificationPrefsRepository repository})
      : _repository = repository;

  final NotificationPrefsRepository _repository;

  @override
  Stream<Either<Failure, NotificationPrefs>> call(NoParams params) =>
      _repository.watchPrefs();
}

class SetNotificationCategoryParams {
  const SetNotificationCategoryParams(this.category, {required this.on});

  final NotificationCategory category;
  final bool on;
}

/// One switch in Settings → Notifications (AC3).
class SetNotificationCategory
    implements AsyncUseCase<Unit, SetNotificationCategoryParams> {
  const SetNotificationCategory(
      {required NotificationPrefsRepository repository})
      : _repository = repository;

  final NotificationPrefsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(SetNotificationCategoryParams params) =>
      _repository.setCategory(params.category, params.on);
}

class SetGroupMutedParams {
  const SetGroupMutedParams(this.groupId, {required this.muted, this.current});

  final String groupId;
  final bool muted;

  /// The choices as last seen, to refuse a mute past [maxMutedGroups].
  final NotificationPrefs? current;
}

/// Mute or unmute a group's activity on every device (AC4).
class SetGroupMuted implements AsyncUseCase<Unit, SetGroupMutedParams> {
  const SetGroupMuted({required NotificationPrefsRepository repository})
      : _repository = repository;

  final NotificationPrefsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(SetGroupMutedParams params) async {
    final muted = params.current?.mutedGroups ?? const [];
    if (params.muted &&
        !muted.contains(params.groupId) &&
        muted.length >= maxMutedGroups) {
      return left(const NotificationFailure.tooManyMutedGroups());
    }
    return _repository.setGroupMuted(params.groupId, params.muted);
  }
}
