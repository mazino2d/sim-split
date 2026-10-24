import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsplit/data/daos/telemetry_dao.dart';
import 'package:simsplit/data/telemetry/scrubber.dart';
import 'package:simsplit/data/telemetry/telemetry_sender.dart';
import 'package:simsplit/domain/entities/telemetry/error_report_settings.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/telemetry_repository.dart';

/// Facts about the device and session that go into every error report.
class TelemetryContext {
  const TelemetryContext({
    required this.platform,
    required this.os,
    required this.appVersion,
    required this.language,
    required this.currentUid,
    required this.knownNames,
  });

  /// 'android' | 'ios' | 'web'
  final String platform;
  final String? os;
  final Future<String> Function() appVersion;
  final Future<String?> Function() language;

  /// The signed-in account, or null; usage events are only recorded while
  /// signed in (AC9).
  final String? Function() currentUid;

  /// Group and member names on this device and the account's name, scrubbed
  /// from messages and stacks (AC4).
  final Future<List<String>> Function() knownNames;
}

/// Error reports and usage events (R-4): an in-memory breadcrumb trail, a
/// per-session dedupe, daily caps, scrubbing, and a Drift queue drained by
/// [TelemetrySender].
class DriftTelemetryRepository implements TelemetryRepository {
  DriftTelemetryRepository({
    required TelemetryDao dao,
    required TelemetrySender sender,
    required TelemetryContext context,
    Scrubber scrubber = const Scrubber(),
    DateTime Function()? now,
    Random? random,
  })  : _dao = dao,
        _sender = sender,
        _context = context,
        _scrubber = scrubber,
        _now = now ?? DateTime.now,
        _random = random ?? Random.secure() {
    _sessionId = _randomId(12, _sessionAlphabet);
    _ready = _loadSettings();
  }

  final TelemetryDao _dao;
  final TelemetrySender _sender;
  final TelemetryContext _context;
  final Scrubber _scrubber;
  final DateTime Function() _now;
  final Random _random;

  static const maxQueuedErrors = 50;
  static const maxErrorsPerDay = 50;
  static const maxQueuedEvents = 2000;
  static const maxEventsPerDay = 5000;
  static const _sessionTimeout = Duration(minutes: 30);
  static const _maxBreadcrumbs = 30;
  static const _enabledKey = 'telemetry.error_reports_enabled';
  static const _reportIdKey = 'telemetry.report_id';
  static const _dayKey = 'telemetry.errors_day';
  static const _dayCountKey = 'telemetry.errors_day_count';
  static const _eventsDayKey = 'telemetry.events_day';
  static const _eventsDayCountKey = 'telemetry.events_day_count';
  // No 0/O or 1/I/L, so the ID reads aloud unambiguously (AC27).
  static const _reportAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _sessionAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  late String _sessionId;
  DateTime? _backgroundedAt;
  String? _currentScreen;
  late final Future<void> _ready;
  final _breadcrumbs = <Breadcrumb>[];
  // Same error (type and stack) → its queued row and payload, this session.
  final _seen = <String, (int, Map<String, Object?>)>{};
  // Fires when the switch changes, so watchers re-read the settings.
  final _settings = StreamController<void>.broadcast();
  bool _enabled = true;
  String? _reportId;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    _reportId = _enabled ? prefs.getString(_reportIdKey) : null;
    if (_enabled && _reportId == null) {
      _reportId = _newReportId();
      await prefs.setString(_reportIdKey, _reportId!);
    }
    _sender
      ..schedule()
      ..startEventTimer();
  }

  String _newReportId() {
    final raw = _randomId(6, _reportAlphabet);
    return '${raw.substring(0, 3)}-${raw.substring(3)}';
  }

  String _randomId(int length, String alphabet) => String.fromCharCodes(
        List.generate(length,
            (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length))),
      );

  @override
  void track(BreadcrumbKind kind, String name,
      {String? result, Duration? duration}) {
    try {
      _track(kind, name, result, duration);
    } on Object {
      // Telemetry never gets in the user's way (AC17).
    }
  }

  void _track(
      BreadcrumbKind kind, String name, String? result, Duration? duration) {
    final time = _now();
    if (kind == BreadcrumbKind.screen) _currentScreen = name;
    if (_enabled) {
      _breadcrumbs.add(Breadcrumb(time: time, kind: kind, name: name));
      if (_breadcrumbs.length > _maxBreadcrumbs) _breadcrumbs.removeAt(0);
    }
    final uid = _context.currentUid();
    if (uid == null) return;
    // Everything about the moment is captured now, before any await.
    final event = (
      uid: uid,
      session: _sessionId,
      screen: _currentScreen,
      time: time,
    );
    unawaited(
        _recordEvent(event, kind, name, result, duration).catchError((_) {}));
  }

  Future<void> _recordEvent(
      ({String uid, String session, String? screen, DateTime time}) event,
      BreadcrumbKind kind,
      String name,
      String? result,
      Duration? duration) async {
    if (!await _takeDailySlot(
        _eventsDayKey, _eventsDayCountKey, maxEventsPerDay)) {
      return;
    }
    final payload = <String, Object?>{
      'uid': event.uid,
      'session_id': event.session,
      'client_time': event.time.millisecondsSinceEpoch,
      'kind': kind.name,
      'name': name,
      'screen': event.screen,
      'result': result,
      'duration_ms': duration?.inMilliseconds,
      'platform': _context.platform,
      'app_version': await _context.appVersion(),
      'language': await _context.language(),
      'online': _sender.lastReachedServer,
    };
    await _dao.enqueue(TelemetrySender.eventKind, jsonEncode(payload),
        max: maxQueuedEvents);
  }

  @override
  void setForeground(bool foreground) {
    if (!foreground) {
      _backgroundedAt = _now();
      _sender.stopEventTimer();
      unawaited(_sender.flushEvents());
      return;
    }
    final away = _backgroundedAt;
    if (away != null && _now().difference(away) >= _sessionTimeout) {
      _sessionId = _randomId(12, _sessionAlphabet);
    }
    _backgroundedAt = null;
    _sender.startEventTimer();
  }

  @override
  void recordError(Object error, StackTrace? stack,
      {required bool shownToUser}) {
    // Captured now, so the trail matches the moment of the error.
    final breadcrumbs = List<Breadcrumb>.of(_breadcrumbs);
    final time = _now();
    final session = _sessionId;
    unawaited(_record(error, stack, breadcrumbs, time, session, shownToUser)
        .catchError((_) {}));
  }

  Future<void> _record(
      Object error,
      StackTrace? stack,
      List<Breadcrumb> breadcrumbs,
      DateTime time,
      String session,
      bool shownToUser) async {
    // An error during start-up waits for the settings, then is dropped if
    // reports are off.
    await _ready;
    if (!_enabled || _reportId == null) return;

    final stackText = stack?.toString();
    final key = '${error.runtimeType}\n${stackText ?? error}';
    final seen = _seen[key];
    if (seen != null) {
      // AC15: once per session, with a count.
      final (rowId, payload) = seen;
      payload['count'] = (payload['count'] as int) + 1;
      await _dao.updatePayload(rowId, jsonEncode(payload));
      return;
    }
    if (!await _takeDailySlot(_dayKey, _dayCountKey, maxErrorsPerDay)) return;

    final names = await _context.knownNames();
    String clean(String s, int max) {
      final scrubbed = _scrubber.scrub(s, knownNames: names);
      return scrubbed.length > max ? scrubbed.substring(0, max) : scrubbed;
    }

    final payload = <String, Object?>{
      'report_id': _reportId,
      'session_id': session,
      'client_time': time.millisecondsSinceEpoch,
      'platform': _context.platform,
      'os': _context.os,
      'app_version': await _context.appVersion(),
      'language': await _context.language(),
      'signed_in': _context.currentUid() != null,
      'online': _sender.lastReachedServer,
      // Failures the app displayed are kept apart from uncaught errors.
      'error_type':
          clean('${shownToUser ? 'shown:' : ''}${_errorType(error)}', 128),
      'message': clean(error.toString(), 2000),
      'stack': stackText == null ? null : clean(stackText, 16000),
      'count': 1,
      'breadcrumbs': [
        for (final b in breadcrumbs)
          {
            'time': b.time.millisecondsSinceEpoch,
            'kind': b.kind.name,
            'name': b.name,
          },
      ],
    };
    final rowId = await _dao.enqueue(
        TelemetrySender.errorKind, jsonEncode(payload),
        max: maxQueuedErrors);
    _seen[key] = (rowId, payload);
    _sender.schedule();
  }

  String _errorType(Object error) {
    final type = error.runtimeType.toString();
    // Unwrap the presentation layer's FailureException(…) to the failure.
    final inner = RegExp(r'^FailureException\((\w+)\)$').firstMatch('$error');
    return inner?.group(1) ?? type;
  }

  Future<bool> _takeDailySlot(String dayKey, String countKey, int max) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _now().toIso8601String().substring(0, 10);
    final count =
        prefs.getString(dayKey) == today ? prefs.getInt(countKey) ?? 0 : 0;
    if (count >= max) return false;
    await prefs.setString(dayKey, today);
    await prefs.setInt(countKey, count + 1);
    return true;
  }

  @override
  Stream<Either<Failure, ErrorReportSettings>>
      watchErrorReportSettings() async* {
    await _ready;
    final appVersion = await _context.appVersion();
    ErrorReportSettings current(int waiting) => ErrorReportSettings(
          enabled: _enabled,
          reportId: _reportId,
          waitingCount: waiting,
          appVersion: appVersion,
          platform: _context.platform,
        );
    var waiting = 0;
    final updates = StreamController<ErrorReportSettings>();
    final counts = _dao.watchCount(TelemetrySender.errorKind).listen((n) {
      waiting = n;
      updates.add(current(n));
    });
    final toggles =
        _settings.stream.listen((_) => updates.add(current(waiting)));
    updates.onCancel = () async {
      await counts.cancel();
      await toggles.cancel();
      await updates.close();
    };
    yield right(current(waiting));
    yield* updates.stream.map(right);
  }

  @override
  Future<Either<Failure, Unit>> setErrorReportsEnabled(bool enabled) async {
    try {
      await _ready;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, enabled);
      if (enabled) {
        // AC26: a new report ID each time reports are turned back on.
        _reportId = _newReportId();
        await prefs.setString(_reportIdKey, _reportId!);
      } else {
        _reportId = null;
        await prefs.remove(_reportIdKey);
        _breadcrumbs.clear();
        _seen.clear();
        await _dao.clear(TelemetrySender.errorKind);
      }
      _enabled = enabled;
      _settings.add(null);
      return right(unit);
    } on Object catch (e) {
      return left(Failure.unexpected(e.toString()));
    }
  }
}
