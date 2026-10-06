import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/activity_entry.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

/// A group's change history (R-3). Entries can only be added, together
/// with the change they describe; nothing edits or deletes them (AC28).
abstract interface class ActivityRepository {
  /// Every entry of [groupId], newest first.
  Stream<Either<Failure, List<ActivityEntry>>> watchActivity(String groupId);
}
