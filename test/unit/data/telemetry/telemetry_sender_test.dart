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
}
