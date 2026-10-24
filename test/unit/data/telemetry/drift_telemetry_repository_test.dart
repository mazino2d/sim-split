import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/repositories/drift_telemetry_repository.dart';
import 'package:simsplit/data/telemetry/telemetry_sender.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/failures/group_failure.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  DriftTelemetryRepository repository({DateTime? now, String? uid = 'uid1'}) =>
      DriftTelemetryRepository(
        dao: db.telemetryDao,
        // No endpoint: reports stay queued so the tests can read them.
        sender: TelemetrySender(
          dao: db.telemetryDao,
          client: MockClient((_) async => http.Response('', 202)),
          endpoint: null,
          appCheckToken: () async => null,
          idToken: () async => null,
        ),
        context: TelemetryContext(
          platform: 'android',
          os: 'android 14',
          appVersion: () async => '2026.10.22+1',
          language: () async => 'vi',
          currentUid: () => uid,
          knownNames: () async => ['Đà Lạt trip', 'Bảo'],
        ),
        now: now == null ? null : () => now,
        random: Random(1),
      );

  Future<List<Map<String, dynamic>>> queued() async {
    // Recording is fire-and-forget; let it finish.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final rows = await db.telemetryDao.oldest('error', 100);
    return [
      for (final r in rows) jsonDecode(r.payload) as Map<String, dynamic>
    ];
  }

  test(
      'an uncaught error is queued with its context and breadcrumbs (AC1, AC3)',
      () async {
    final repo = repository();
    repo
      ..track(BreadcrumbKind.screen, '/groups/:groupId')
      ..track(BreadcrumbKind.op, TelemetryEvent.opAddExpense.wireName)
      ..recordError(StateError('Bad state'), StackTrace.current,
          shownToUser: false);
    final [report] = await queued();
    expect(report['report_id'], matches(RegExp(r'^[A-Z2-9]{3}-[A-Z2-9]{3}$')));
    expect(report['platform'], 'android');
    expect(report['app_version'], '2026.10.22+1');
    expect(report['language'], 'vi');
    expect(report['signed_in'], isTrue);
    expect(report['error_type'], 'StateError');
    expect(report['count'], 1);
    expect([
      for (final b
          in (report['breadcrumbs'] as List).cast<Map<String, dynamic>>())
        b['name'],
    ], [
      '/groups/:groupId',
      'op_add_expense'
    ]);
  });

  test('a report never holds names, emails, IDs or amounts (AC4)', () async {
    final repo = repository();
    repo.recordError(
      Exception('Bảo (bao@example.com) paid 1,250,000 in Đà Lạt trip, '
          'groups/aB3dE5fG7hJ9kL1mN2pQ, uid kT9mPq2Lr8Xs4Vw6Yz1Ab3Cd'),
      null,
      shownToUser: true,
    );
    final text = jsonEncode(await queued());
    for (final leaked in [
      'Bảo',
      'bao@example.com',
      '1,250,000',
      'Đà Lạt',
      'aB3dE5fG7hJ9kL1mN2pQ',
      'kT9mPq2Lr8Xs4Vw6Yz1Ab3Cd',
    ]) {
      expect(text, isNot(contains(leaked)));
    }
  });

  test(
      'a failure shown to the user is reported apart from uncaught errors (AC2)',
      () async {
    repository()
        .recordError(const GroupFailure.notFound(), null, shownToUser: true);
    final [report] = await queued();
    expect(report['error_type'], startsWith('shown:'));
  });

  test('the same error is sent once per session, with a count (AC15)',
      () async {
    final repo = repository();
    final stack = StackTrace.current;
    for (var i = 0; i < 3; i++) {
      repo.recordError(StateError('x'), stack, shownToUser: false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final reports = await queued();
    expect(reports, hasLength(1));
    expect(reports.single['count'], 3);
  });

  test('at most 50 error reports a day (AC16)', () async {
    final repo = repository(now: DateTime.utc(2026, 10, 24, 3));
    for (var i = 0; i < 55; i++) {
      repo.recordError(StateError('error $i'), StackTrace.fromString('#$i'),
          shownToUser: false);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await queued(), hasLength(50));
  });

  test(
      'turning reports off records nothing and deletes waiting ones; '
      'turning them on gives a new report ID (AC26)', () async {
    final repo = repository();
    repo.recordError(StateError('before'), null, shownToUser: false);
    expect(await queued(), hasLength(1));
    final before = (await repo.watchErrorReportSettings().first)
        .getOrElse((_) => throw StateError('settings'));

    await repo.setErrorReportsEnabled(false);
    repo.recordError(StateError('while off'), null, shownToUser: false);
    expect(await queued(), isEmpty);
    final off = (await repo.watchErrorReportSettings().first)
        .getOrElse((_) => throw StateError('settings'));
    expect((off.enabled, off.reportId), (false, null));

    await repo.setErrorReportsEnabled(true);
    final on = (await repo.watchErrorReportSettings().first)
        .getOrElse((_) => throw StateError('settings'));
    expect(on.enabled, isTrue);
    expect(on.reportId, isNot(before.reportId));
  });

  test('the choice and the report ID survive a restart (AC28)', () async {
    final first = (await repository().watchErrorReportSettings().first)
        .getOrElse((_) => throw StateError('settings'));
    final again = (await repository().watchErrorReportSettings().first)
        .getOrElse((_) => throw StateError('settings'));
    expect(again.reportId, first.reportId);
  });

  Future<List<Map<String, dynamic>>> events() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final rows = await db.telemetryDao.oldest('event', 100);
    return [
      for (final r in rows) jsonDecode(r.payload) as Map<String, dynamic>
    ];
  }

  test(
      'screens and operations become usage events of the signed-in account '
      '(AC8)', () async {
    repository()
      ..track(BreadcrumbKind.screen, '/groups/:groupId')
      ..track(BreadcrumbKind.op, TelemetryEvent.opAddExpense.wireName,
          result: 'success', duration: const Duration(milliseconds: 120));
    final [screen, op] = await events();
    expect((screen['uid'], screen['kind'], screen['name']),
        ('uid1', 'screen', '/groups/:groupId'));
    expect(
        (op['kind'], op['name'], op['screen'], op['result'], op['duration_ms']),
        ('op', 'op_add_expense', '/groups/:groupId', 'success', 120));
    expect(op['session_id'], screen['session_id']);
  });

  test('nothing is tracked as usage before sign-in (AC9)', () async {
    repository(uid: null).track(BreadcrumbKind.screen, '/sign-in');
    expect(await events(), isEmpty);
  });

  test('usage events do not depend on the error report switch', () async {
    final repo = repository();
    await repo.setErrorReportsEnabled(false);
    repo.track(BreadcrumbKind.screen, '/');
    expect(await events(), hasLength(1));
  });

  test('a new session starts after 30 minutes in the background', () async {
    var now = DateTime.utc(2026, 10, 24, 3);
    final repo = DriftTelemetryRepository(
      dao: db.telemetryDao,
      sender: TelemetrySender(
        dao: db.telemetryDao,
        client: MockClient((_) async => http.Response('', 202)),
        endpoint: null,
        appCheckToken: () async => null,
        idToken: () async => null,
      ),
      context: TelemetryContext(
        platform: 'web',
        os: null,
        appVersion: () async => '1',
        language: () async => 'en',
        currentUid: () => 'uid1',
        knownNames: () async => [],
      ),
      now: () => now,
    );
    repo.track(BreadcrumbKind.screen, '/');
    repo.setForeground(false);
    now = now.add(const Duration(minutes: 10));
    repo
      ..setForeground(true)
      ..track(BreadcrumbKind.screen, '/settings')
      ..setForeground(false);
    now = now.add(const Duration(minutes: 31));
    repo
      ..setForeground(true)
      ..track(BreadcrumbKind.screen, '/');
    final sessions = [for (final e in await events()) e['session_id']];
    expect(sessions[0], sessions[1]);
    expect(sessions[2], isNot(sessions[1]));
  });
}
