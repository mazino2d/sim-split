import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/activity_entry.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/activity_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// A group's change history, newest first (AC25).
class WatchActivity implements StreamUseCase<List<ActivityEntry>, String> {
  const WatchActivity({required ActivityRepository activityRepository})
      : _activityRepository = activityRepository;

  final ActivityRepository _activityRepository;

  @override
  Stream<Either<Failure, List<ActivityEntry>>> call(String groupId) =>
      _activityRepository.watchActivity(groupId);
}
