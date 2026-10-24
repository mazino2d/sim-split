import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' show Either;

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/telemetry/track_event.dart';

/// Every interactive callback in `lib/presentation` goes through one of these
/// (R-4 AC8, AC8a): a tap, a choice, a gesture or a form step becomes a usage
/// event and a breadcrumb named from [TelemetryEvent], never from free text.
/// `test/unit/presentation/tracking_coverage_test.dart` fails the build on a
/// callback that is not tracked.
extension Tracking on BuildContext {
  /// Resolved when the callback is built; the tracker itself is read when
  /// the callback runs, inside the guard.
  void Function(TelemetryEvent) get _tracker {
    final container = ProviderScope.containerOf(this, listen: false);
    return _safe(() => container.read(trackEventProvider));
  }

  /// Wraps a callback so calling it records [event] first; null stays null,
  /// so disabled buttons stay disabled.
  VoidCallback? tracked(TelemetryEvent event, VoidCallback? callback) {
    if (callback == null) return null;
    final track = _tracker;
    return () {
      track(event);
      callback();
    };
  }

  /// Like [tracked], for callbacks that receive a value (a chip, a switch,
  /// a menu item).
  ValueChanged<T>? trackedValue<T>(
      TelemetryEvent event, ValueChanged<T>? callback) {
    if (callback == null) return null;
    final track = _tracker;
    return (value) {
      track(event);
      callback(value);
    };
  }

  /// [tracked] for parameters that cannot be null.
  VoidCallback trackedCall(TelemetryEvent event, VoidCallback callback) =>
      tracked(event, callback)!;

  /// [trackedValue] for parameters that cannot be null.
  void Function(T) trackedValueCall<T>(
          TelemetryEvent event, void Function(T) callback) =>
      trackedValue<T>(event, callback)!;

  /// Records [event] now, for steps that are not a callback.
  void track(TelemetryEvent event) => _tracker(event);
}

/// A tracker that can never throw into the user's action (AC17).
void Function(TelemetryEvent) _safe(TrackEvent Function() track) => (event) {
      try {
        track()(event.kind, event.wireName);
      } on Object {
        // Telemetry never gets in the user's way.
      }
    };

/// Runs a use case and records it as an operation with its result
/// (`success`, or the failure type in snake_case) and duration (AC8).
Future<Either<Failure, T>> trackOp<T>(
  TrackEvent track,
  TelemetryEvent event,
  Future<Either<Failure, T>> Function() action,
) async {
  final watch = Stopwatch()..start();
  final result = await action();
  track(
    BreadcrumbKind.op,
    event.wireName,
    result: result.fold((f) => failureName(f), (_) => 'success'),
    duration: watch.elapsed,
  );
  return result;
}

/// `GroupNameTooShort` → `group_name_too_short`.
String failureName(Failure failure) => failure.runtimeType
    .toString()
    .replaceAllMapped(RegExp('(?<=[a-z0-9])[A-Z]'), (m) => '_${m[0]}')
    .toLowerCase();

/// Records dialogs, bottom sheets and menus opening and closing (AC8). Their
/// content is never named: the screen they open over says where.
class TelemetryNavigatorObserver extends NavigatorObserver {
  TelemetryNavigatorObserver(this._track);

  final TrackEvent Function() _track;

  bool _isPopup(Route<dynamic> route) => route is PopupRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isPopup(route)) {
      _track()(BreadcrumbKind.dialog, TelemetryEvent.dialogOpened.wireName);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isPopup(route)) {
      _track()(BreadcrumbKind.dialog, TelemetryEvent.dialogClosed.wireName);
    }
  }
}

/// Records a form screen as submitted when its save succeeds, or abandoned
/// when it closes without one (R-4 AC8). Call [markSubmitted] on success.
mixin TrackedForm<W extends StatefulWidget> on State<W> {
  TelemetryEvent get formSubmitted;
  TelemetryEvent get formAbandoned;

  TrackEvent? _formTrack;
  bool _formSubmitted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _formTrack ??= ProviderScope.containerOf(context, listen: false)
        .read(trackEventProvider);
  }

  void markSubmitted() {
    if (_formSubmitted) return;
    _formSubmitted = true;
    _formTrack?.call(formSubmitted.kind, formSubmitted.wireName);
  }

  @override
  void dispose() {
    if (!_formSubmitted) {
      _formTrack?.call(formAbandoned.kind, formAbandoned.wireName);
    }
    super.dispose();
  }
}
