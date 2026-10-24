import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/telemetry/telemetry_sender.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  final endpoint = Uri.parse('https://telemetry.example');

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> queue(int n) async {
    for (var i = 0; i < n; i++) {
      await db.telemetryDao.enqueue('error', jsonEncode({'n': i}), max: 50);
    }
  }

  TelemetrySender sender(http.Client client, {Uri? to}) => TelemetrySender(
        dao: db.telemetryDao,
        client: client,
        endpoint: to ?? endpoint,
        appCheckToken: () async => 'app-check',
        idToken: () async => 'id-token',
      );

  test('sends queued reports with the App Check token and removes them',
      () async {
    final requests = <http.Request>[];
    await queue(25);
    final s = sender(MockClient((request) async {
      requests.add(request);
      return http.Response('{}', 202);
    }));
    await s.flushErrors();
    expect(requests, hasLength(2));
    expect(requests.first.url.path, '/v1/errors');
    expect(requests.first.headers['x-firebase-appcheck'], 'app-check');
    expect((jsonDecode(requests.first.body) as Map)['reports'], hasLength(20));
    expect(await db.telemetryDao.watchCount('error').first, 0);
    s.dispose();
  });

  test('keeps reports queued when the endpoint is down or offline', () async {
    await queue(3);
    final down = sender(MockClient((_) async => http.Response('', 503)));
    await down.flushErrors();
    expect(await db.telemetryDao.watchCount('error').first, 3);
    down.dispose();

    final offline = sender(MockClient((_) => throw http.ClientException('x')));
    await offline.flushErrors();
    expect(await db.telemetryDao.watchCount('error').first, 3);
    expect(offline.lastReachedServer, isFalse);
    offline.dispose();
  });

  test('drops reports the endpoint rejects as invalid', () async {
    await queue(2);
    final s = sender(MockClient((_) async => http.Response('', 400)));
    await s.flushErrors();
    expect(await db.telemetryDao.watchCount('error').first, 0);
    s.dispose();
  });

  test('sends nothing without an endpoint', () async {
    await queue(1);
    var called = false;
    final s = TelemetrySender(
      dao: db.telemetryDao,
      client: MockClient((_) async {
        called = true;
        return http.Response('', 202);
      }),
      endpoint: null,
      appCheckToken: () async => null,
      idToken: () async => null,
    );
    await s.flushErrors();
    expect(called, isFalse);
    expect(await db.telemetryDao.watchCount('error').first, 1);
  });

  test('the queue keeps only the newest items of a kind', () async {
    await queue(55);
    final rows = await db.telemetryDao.oldest('error', 100);
    expect(rows, hasLength(50));
    expect(jsonDecode(rows.first.payload), {'n': 5});
  });

  test('sends usage events in batches with the account ID token (AC14)',
      () async {
    for (var i = 0; i < 3; i++) {
      await db.telemetryDao.enqueue('event', jsonEncode({'n': i}), max: 2000);
    }
    final requests = <http.Request>[];
    final s = sender(MockClient((request) async {
      requests.add(request);
      return http.Response('{}', 202);
    }));
    await s.flushEvents();
    expect(requests.single.url.path, '/v1/events');
    expect(requests.single.headers['authorization'], 'Bearer id-token');
    expect((jsonDecode(requests.single.body) as Map)['events'], hasLength(3));
    expect(await db.telemetryDao.watchCount('event').first, 0);
    s.dispose();
  });

  test('drops events of an account that is no longer signed in', () async {
    await db.telemetryDao.enqueue('event', '{}', max: 2000);
    final s = sender(MockClient((_) async => http.Response('', 403)));
    await s.flushEvents();
    expect(await db.telemetryDao.watchCount('event').first, 0);
    s.dispose();
  });

  test('events from the end of a session use the last ID token', () async {
    String? token = 'id-token';
    final seen = <String?>[];
    final s = TelemetrySender(
      dao: db.telemetryDao,
      client: MockClient((request) async {
        seen.add(request.headers['authorization']);
        return http.Response('{}', 202);
      }),
      endpoint: endpoint,
      appCheckToken: () async => 'app-check',
      idToken: () async => token,
    );
    await db.telemetryDao.enqueue('event', '{}', max: 2000);
    await s.flushEvents();
    token = null;
    await db.telemetryDao.enqueue('event', '{}', max: 2000);
    await s.flushEvents();
    expect(seen, ['Bearer id-token', 'Bearer id-token']);
    s.dispose();
  });
}
