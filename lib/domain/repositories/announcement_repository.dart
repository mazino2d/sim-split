import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/notifications/announcement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

/// In-app banners (R-9 AC12) and which ones the account dismissed.
abstract interface class AnnouncementRepository {
  /// Announcements addressed to the signed-in account or to everyone that
  /// have not ended yet.
  Stream<Either<Failure, List<Announcement>>> watchAnnouncements();

  /// IDs of the announcements the account dismissed, on any device.
  Stream<Either<Failure, Set<String>>> watchDismissed();

  /// Remembers [id] as dismissed for the account, keeping at most
  /// [maxDismissedAnnouncements] (the oldest go first).
  Future<Either<Failure, Unit>> dismiss(String id);
}
