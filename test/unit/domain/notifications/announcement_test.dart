import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/notifications/announcement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/announcement_repository.dart';
import 'package:simsplit/domain/use_cases/announcements/announcements.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class _MockRepo extends Mock implements AnnouncementRepository {}

final _now = DateTime(2026, 12, 1, 12);

Announcement _a(String id, {int hours = 24}) => Announcement(
      id: id,
      copy: const {
        'en': AnnouncementCopy(title: 'Title', body: 'Body'),
        'vi': AnnouncementCopy(title: 'Tiêu đề', body: 'Nội dung'),
      },
      endsAt: _now.add(Duration(hours: hours)),
    );

void main() {
  group('pickAnnouncement (R-9 AC12)', () {
    test('shows one: the active, undismissed one that ends first', () {
      final picked = pickAnnouncement(
          [_a('later', hours: 48), _a('soon', hours: 2), _a('gone', hours: -1)],
          {},
          _now);
      expect(picked?.id, 'soon');
    });

    test('skips dismissed and ended ones; none left is null', () {
      expect(
          pickAnnouncement([_a('soon', hours: 2), _a('later', hours: 48)],
                  {'soon'}, _now)
              ?.id,
          'later');
      expect(pickAnnouncement([_a('gone', hours: -1)], {}, _now), isNull);
      expect(pickAnnouncement([], {}, _now), isNull);
    });

    test('ties on the end time go by id', () {
      expect(pickAnnouncement([_a('b'), _a('a')], {}, _now)?.id, 'a');
    });
  });

  test('the copy falls back to English', () {
    final a = Announcement(
        id: 'x1',
        copy: const {'en': AnnouncementCopy(title: 'T', body: 'B')},
        endsAt: _now);
    expect(a.copyFor('vi')?.title, 'T');
  });

  test('config ids become usage results; anything else is refused', () {
    expect(configIdResult('campaign', '2026-12-01-new-version'),
        'campaign_2026_12_01_new_version');
    expect(configIdResult('campaign', 'Has Spaces'), isNull);
    expect(configIdResult('campaign', 'x'), isNull);
    expect(configIdResult('campaign', 'a' * 63)!.length, 64);
  });

  group('WatchAnnouncement', () {
    late _MockRepo repo;
    late StreamController<Either<Failure, List<Announcement>>> announcements;
    late StreamController<Either<Failure, Set<String>>> dismissed;

    setUp(() {
      repo = _MockRepo();
      announcements = StreamController();
      dismissed = StreamController();
      when(() => repo.watchAnnouncements())
          .thenAnswer((_) => announcements.stream);
      when(() => repo.watchDismissed()).thenAnswer((_) => dismissed.stream);
    });

    tearDown(() async {
      await announcements.close();
      await dismissed.close();
    });

    test('combines the announcements with what the account dismissed',
        () async {
      final out = <String?>[];
      final sub =
          WatchAnnouncement(repository: repo, now: () => _now)(const NoParams())
              .listen((e) => out.add(e.toNullable()?.id));

      announcements.add(right([_a('one'), _a('two', hours: 48)]));
      await pumpEventQueue();
      expect(out, isEmpty, reason: 'waits for the dismissed list');
      dismissed.add(right({}));
      await pumpEventQueue();
      dismissed.add(right({'one'}));
      await pumpEventQueue();
      dismissed.add(right({'one', 'two'}));
      await pumpEventQueue();

      expect(out, ['one', 'two', null]);
      await sub.cancel();
    });
  });
}
