import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show Either, Unit, left, right, unit;
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/entities/telemetry/error_report_settings.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/repositories/telemetry_repository.dart';
import 'package:simsplit/domain/use_cases/telemetry/track_event.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

class _Recorder implements TelemetryRepository {
  final tracked = <(BreadcrumbKind, String, String?)>[];
  bool fail = false;

  @override
  void track(BreadcrumbKind kind, String name,
      {String? result, Duration? duration}) {
    if (fail) throw StateError('telemetry down');
    tracked.add((kind, name, result));
  }

  @override
  void setForeground(bool foreground) {}
  @override
  void recordError(Object error, StackTrace? stack,
      {required bool shownToUser}) {}
  @override
  Stream<Either<Failure, ErrorReportSettings>> watchErrorReportSettings() =>
      const Stream.empty();
  @override
  Future<Either<Failure, Unit>> setErrorReportsEnabled(bool enabled) async =>
      right(unit);
}

class _Form extends StatefulWidget {
  const _Form({required this.submit});
  final bool submit;
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> with TrackedForm<_Form> {
  @override
  TelemetryEvent get formSubmitted => TelemetryEvent.formGroupSubmitted;
  @override
  TelemetryEvent get formAbandoned => TelemetryEvent.formGroupAbandoned;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: widget.submit ? markSubmitted : null,
        child: const Text('save'),
      );
}

void main() {
  late _Recorder recorder;
  setUp(() => recorder = _Recorder());

  Widget app(Widget child) => ProviderScope(
        overrides: [
          trackEventProvider
              .overrideWithValue(TrackEvent(telemetryRepository: recorder)),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  test('event names are snake_case and their prefix gives the kind', () {
    expect(TelemetryEvent.tapSaveExpense.wireName, 'tap_save_expense');
    expect(TelemetryEvent.tapSaveExpense.kind, BreadcrumbKind.tap);
    expect(TelemetryEvent.formGroupAbandoned.kind, BreadcrumbKind.form);
    expect(TelemetryEvent.dialogOpened.kind, BreadcrumbKind.dialog);
    expect(
        TelemetryEvent.gestureSwipeDeleteExpense.kind, BreadcrumbKind.gesture);
    expect(TelemetryEvent.opCreateGroup.kind, BreadcrumbKind.op);
  });

  test('every event name fits the endpoint schema', () {
    final valid = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
    for (final e in TelemetryEvent.values) {
      expect(valid.hasMatch(e.wireName), isTrue, reason: e.wireName);
    }
  });

  test('trackOp records the result and duration of a use case', () async {
    final track = TrackEvent(telemetryRepository: recorder);
    await trackOp(track, TelemetryEvent.opCreateGroup,
        () async => right<Failure, int>(1));
    await trackOp(track, TelemetryEvent.opCreateGroup,
        () async => left<Failure, int>(const GroupFailure.nameTooShort()));
    expect(recorder.tracked, [
      (BreadcrumbKind.op, 'op_create_group', 'success'),
      (BreadcrumbKind.op, 'op_create_group', 'group_name_too_short'),
    ]);
  });

  testWidgets('a tracked tap records its event, then runs the callback',
      (tester) async {
    var pressed = 0;
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed:
            context.tracked(TelemetryEvent.tapSaveGroup, () => pressed++),
        child: const Text('save'),
      ),
    )));
    await tester.tap(find.text('save'));
    expect(recorder.tracked, [(BreadcrumbKind.tap, 'tap_save_group', null)]);
    expect(pressed, 1);
  });

  testWidgets('a disabled button stays disabled', (tester) async {
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: context.tracked(TelemetryEvent.tapSaveGroup, null),
        child: const Text('save'),
      ),
    )));
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
  });

  testWidgets('a telemetry failure never blocks the action (AC17)',
      (tester) async {
    recorder.fail = true;
    var pressed = 0;
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed:
            context.tracked(TelemetryEvent.tapSaveGroup, () => pressed++),
        child: const Text('save'),
      ),
    )));
    await tester.tap(find.text('save'));
    expect(pressed, 1);
  });

  testWidgets('a form closed after saving is submitted, otherwise abandoned',
      (tester) async {
    await tester.pumpWidget(app(const _Form(submit: true)));
    await tester.tap(find.text('save'));
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pumpWidget(app(const _Form(submit: false)));
    await tester.pumpWidget(app(const SizedBox()));
    expect([for (final t in recorder.tracked) t.$2],
        ['form_group_submitted', 'form_group_abandoned']);
  });

  testWidgets('dialogs are recorded as opened and closed', (tester) async {
    final observer = TelemetryNavigatorObserver(
        () => TrackEvent(telemetryRepository: recorder));
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (d) => TextButton(
                onPressed: () => Navigator.pop(d), child: const Text('ok')),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ok'));
    await tester.pumpAndSettle();
    expect([for (final t in recorder.tracked) t.$2],
        ['dialog_opened', 'dialog_closed']);
  });
}
