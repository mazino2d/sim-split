import 'dart:async';

import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/notifications/announcement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/announcement_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// The one banner to show now (R-9 AC12), or null: the announcements for
/// the account minus the ones it dismissed on any device. Re-evaluated
/// when either changes, and when the shown one ends.
class WatchAnnouncement implements StreamUseCase<Announcement?, NoParams> {
  WatchAnnouncement({
    required AnnouncementRepository repository,
    DateTime Function()? now,
  })  : _repository = repository,
        _now = now ?? DateTime.now;

  final AnnouncementRepository _repository;
  final DateTime Function() _now;

  @override
  Stream<Either<Failure, Announcement?>> call(NoParams params) {
    late final StreamController<Either<Failure, Announcement?>> controller;
    List<Announcement>? announcements;
    Set<String>? dismissed;
    Timer? expiry;
    final subs = <StreamSubscription<Object?>>[];

    void emit() {
      final all = announcements;
      final gone = dismissed;
      if (all == null || gone == null) return;
      final picked = pickAnnouncement(all, gone, _now());
      controller.add(right(picked));
      expiry?.cancel();
      if (picked != null) {
        expiry = Timer(picked.endsAt.difference(_now()), emit);
      }
    }

    controller = StreamController(
      onListen: () {
        subs
          ..add(_repository.watchAnnouncements().listen(
              (either) => either.fold((f) => controller.add(left(f)), (list) {
                    announcements = list;
                    emit();
                  })))
          ..add(_repository.watchDismissed().listen(
              (either) => either.fold((f) => controller.add(left(f)), (ids) {
                    dismissed = ids;
                    emit();
                  })));
      },
      onCancel: () async {
        expiry?.cancel();
        for (final sub in subs) {
          await sub.cancel();
        }
        await controller.close();
      },
    );
    return controller.stream;
  }
}

/// Dismisses a banner for the account, on every device (AC12).
class DismissAnnouncement implements AsyncUseCase<Unit, String> {
  const DismissAnnouncement({required AnnouncementRepository repository})
      : _repository = repository;

  final AnnouncementRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String id) => _repository.dismiss(id);
}
