import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// R-4 AC8a: no interactive element can be added without an event name.
///
/// Every named callback argument in lib/presentation (`onPressed:`, `onTap:`,
/// `onSelected:`, `onRetry:`, …) must be wrapped in `context.tracked(…)` or
/// `context.trackedValue(…)`, call `context.track(…)`, be `null`, or forward a parameter of the
/// enclosing widget (a bare name without a leading underscore; its caller is
/// checked instead). A callback may opt out with a `// telemetry: <reason>`
/// comment on its line or the next two, e.g. typing in a text field, which is not an action.
void main() {
  final callback = RegExp(r'\b(on[A-Z]\w*)\s*:\s*(.*)$');
  // Colour roles (`onSurface:` …) are not callbacks.
  final colourRole = RegExp(
      r'^on(Primary|Secondary|Tertiary|Surface|Error|Background|Inverse)');

  test('every interactive callback in lib/presentation is tracked', () {
    final untracked = <String>[];
    final files = Directory('lib/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        final match = callback.firstMatch(line);
        if (match == null || colourRole.hasMatch(match.group(1)!)) continue;
        // A callback value may continue on the next lines.
        final value =
            [match.group(2)!, ...lines.skip(i + 1).take(2)].join(' ').trim();
        final ok = value.contains('// telemetry:') ||
            value.startsWith('null') ||
            RegExp(r'\.tracked\w*(<[^>]*>)?\(').hasMatch(value) ||
            value.contains('.track(') ||
            RegExp(r'^[a-z]\w*\s*[,)]').hasMatch(value);
        if (!ok) untracked.add('${file.path}:${i + 1}: ${line.trim()}');
      }
    }
    expect(untracked, isEmpty, reason: untracked.join('\n'));
  });

  test('every use case run from lib/presentation is a tracked operation', () {
    // Telemetry's own use cases and read-only streams are not operations.
    const notOperations = {
      'trackEvent',
      'setAppForeground',
      'recordError',
      'watchErrorReportSettings',
    };
    final call = RegExp(r'ref\.read\((\w+)Provider\)\(');
    final untracked = <String>[];
    for (final file in Directory('lib/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
            (f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final match in call.allMatches(lines[i])) {
          if (notOperations.contains(match.group(1))) continue;
          final before = lines.sublist(i < 3 ? 0 : i - 3, i + 1).join(' ');
          if (!before.contains('trackOp(')) {
            untracked.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(untracked, isEmpty, reason: untracked.join('\n'));
  });
}
