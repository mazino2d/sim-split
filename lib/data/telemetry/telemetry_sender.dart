import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:simsplit/data/daos/telemetry_dao.dart';

/// Drains the telemetry queue to the endpoint in the background (R-4 AC13,
/// AC17). Every failure is silent: items stay queued and are retried with
/// backoff; only items the endpoint rejects as invalid are dropped.
class TelemetrySender {
  TelemetrySender({
    required TelemetryDao dao,
    required http.Client client,
    required Uri? endpoint,
    required Future<String?> Function() appCheckToken,
  })  : _dao = dao,
        _client = client,
        _endpoint = endpoint,
        _appCheckToken = appCheckToken;

  final TelemetryDao _dao;
  final http.Client _client;
  final Uri? _endpoint;
  final Future<String?> Function() _appCheckToken;

  static const errorKind = 'error';
  static const _batchSize = 20;
  static const _maxBackoff = Duration(minutes: 10);

  bool _sending = false;
  Duration _backoff = const Duration(seconds: 5);
  Timer? _retry;

  /// Whether the last request reached the endpoint; reported as `online`.
  bool lastReachedServer = true;

  /// Asks for a send soon; safe to call often.
  void schedule() {
    if (_endpoint == null || _retry != null) return;
    unawaited(flushErrors());
  }

  /// Sends queued error reports until the queue is empty or a request fails.
  Future<void> flushErrors() async {
    final endpoint = _endpoint;
    if (endpoint == null || _sending) return;
    _sending = true;
    try {
      while (true) {
        final batch = await _dao.oldest(errorKind, _batchSize);
        if (batch.isEmpty) break;
        final status = await _post(endpoint.resolve('/v1/errors'), {
          'reports': [for (final row in batch) jsonDecode(row.payload)],
        });
        if (status == 202 || status == 400 || status == 413) {
          // Sent, or rejected for good: either way it must not block the queue.
          await _dao.deleteIds(batch.map((row) => row.id));
          _backoff = const Duration(seconds: 5);
          continue;
        }
        _retryLater();
        break;
      }
    } finally {
      _sending = false;
    }
  }

  Future<int?> _post(Uri url, Map<String, Object?> body) async {
    try {
      final token = await _appCheckToken();
      final response = await _client
          .post(
            url,
            headers: {
              'content-type': 'application/json',
              if (token != null) 'x-firebase-appcheck': token,
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

  void _retryLater() {
    _retry?.cancel();
    _retry = Timer(_backoff, () {
      _retry = null;
      unawaited(flushErrors());
    });
    final next = _backoff * 2;
    _backoff = next > _maxBackoff ? _maxBackoff : next;
  }

  void dispose() => _retry?.cancel();
}
