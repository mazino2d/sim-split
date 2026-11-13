import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:simsplit/data/daos/telemetry_dao.dart';

/// Drains the telemetry queue to the endpoint in the background (R-4 AC13,
/// AC14, AC17). Error reports go right away; usage events in batches: a
/// few seconds after the app opens or comes back, then at most once a
/// minute while it is open, and once when it goes to the background. Every failure is silent: items stay queued and are retried
/// with backoff; only items the endpoint rejects for good are dropped.
class TelemetrySender {
  TelemetrySender({
    required TelemetryDao dao,
    required http.Client client,
    required Uri? endpoint,
    required Future<String?> Function() appCheckToken,
    required Future<String?> Function() idToken,
    Duration firstFlushDelay = const Duration(seconds: 3),
  })  : _firstFlushDelay = firstFlushDelay,
        _dao = dao,
        _client = client,
        _endpoint = endpoint,
        _appCheckToken = appCheckToken,
        _idToken = idToken;

  final TelemetryDao _dao;
  final http.Client _client;
  final Uri? _endpoint;
  final Future<String?> Function() _appCheckToken;
  final Future<String?> Function() _idToken;

  static const errorKind = 'error';
  static const eventKind = 'event';
  static const _errorBatch = 20;
  static const _eventBatch = 500;
  static const _eventInterval = Duration(minutes: 1);
  // Short sessions (a few seconds) never reach the first periodic flush, and
  // the flush on backgrounding is often cut off when Android freezes the
  // process, so their events arrived days late, on the next launch (#128).
  final Duration _firstFlushDelay;
  static const _maxBackoff = Duration(minutes: 10);

  final _sending = <String>{};
  final _backoff = <String, Duration>{};
  final _retry = <String, Timer>{};
  Timer? _eventTimer;
  Timer? _firstFlush;

  // The last ID token seen, so events recorded as the session ends (the
  // sign-out or account deletion itself) can still be sent; the endpoint
  // accepts a token until it expires and checks every event's uid against it.
  String? _lastIdToken;

  /// Whether the last request reached the endpoint; reported as `online`.
  bool lastReachedServer = true;

  /// Asks for error reports to be sent soon; safe to call often.
  void schedule() {
    if (_endpoint == null || _retry.containsKey(errorKind)) return;
    unawaited(flushErrors());
  }

  /// Sends usage events a few seconds after the app opens or comes back,
  /// then once a minute while it stays open.
  void startEventTimer() {
    if (_endpoint == null || _eventTimer != null) return;
    _firstFlush = Timer(_firstFlushDelay, flushEvents);
    _eventTimer = Timer.periodic(_eventInterval, (_) => flushEvents());
  }

  void stopEventTimer() {
    _firstFlush?.cancel();
    _firstFlush = null;
    _eventTimer?.cancel();
    _eventTimer = null;
  }

  Future<void> flushErrors() =>
      _flush(errorKind, '/v1/errors', 'reports', _errorBatch);

  Future<void> flushEvents() =>
      _flush(eventKind, '/v1/events', 'events', _eventBatch);

  Future<void> _flush(String kind, String path, String field, int size) async {
    final endpoint = _endpoint;
    if (endpoint == null || !_sending.add(kind)) return;
    try {
      while (true) {
        final batch = await _dao.oldest(kind, size);
        if (batch.isEmpty) break;
        final status = await _post(
          endpoint.resolve(path),
          {
            field: [for (final row in batch) jsonDecode(row.payload)],
          },
          withIdToken: kind == eventKind,
        );
        // Sent, or rejected for good (invalid, too large, or events of an
        // account that is no longer signed in): it must not block the queue.
        if (const {202, 400, 403, 413}.contains(status)) {
          await _dao.deleteIds(batch.map((row) => row.id));
          _backoff.remove(kind);
          continue;
        }
        _retryLater(kind);
        break;
      }
    } finally {
      _sending.remove(kind);
    }
  }

  Future<int?> _post(Uri url, Map<String, Object?> body,
      {required bool withIdToken}) async {
    try {
      final appCheck = await _appCheckToken();
      String? id;
      if (withIdToken) {
        id = await _idToken() ?? _lastIdToken;
        if (id == null) return null;
        _lastIdToken = id;
      }
      final response = await _client
          .post(
            url,
            headers: {
              'content-type': 'application/json',
              if (appCheck != null) 'x-firebase-appcheck': appCheck,
              if (id != null) 'authorization': 'Bearer $id',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      lastReachedServer = true;
      return response.statusCode;
    } on Object {
      lastReachedServer = false;
      return null;
    }
  }

  void _retryLater(String kind) {
    final delay = _backoff[kind] ?? const Duration(seconds: 5);
    _retry[kind]?.cancel();
    _retry[kind] = Timer(delay, () {
      _retry.remove(kind);
      unawaited(kind == errorKind ? flushErrors() : flushEvents());
    });
    final next = delay * 2;
    _backoff[kind] = next > _maxBackoff ? _maxBackoff : next;
  }

  void dispose() {
    stopEventTimer();
    for (final timer in _retry.values) {
      timer.cancel();
    }
  }
}
