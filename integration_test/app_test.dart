import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:simsplit/main.dart' as app;

/// End-to-end journey through the real app: real Drift database, real
/// router, real providers. Covers the core and supporting use cases in
/// docs/product/use-cases.md on a fresh install.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// testWidgets that also records its failure in the response data, since
  /// profile and release builds drop failure messages from the driver output.
  void e2e(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } catch (e) {
        binding.reportData = {
          ...?binding.reportData,
          description: e.toString(),
        };
        rethrow;
      }
    });
  }

  // The tests run in order and share one on-device database, like a user
  // reopening the app: each one relaunches it on the data the previous left.
  setUpAll(() async {
    // Pin the language so the journey does not depend on the device locale.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale_language_code', 'en');
  });

  e2e('UC-3: sets up a group with members on a fresh install', (tester) async {
    await tester.launch();
    await tester.waitFor(find.text('No groups yet'));

    await tester.tapAndWait(find.text('Create Group'));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Da Lat trip');
    await tester.enterText(fields.at(1), 'Khoi');
    final addPerson = find.widgetWithText(TextField, 'Add a person…');
    for (final name in ['Linh', 'Minh']) {
      await tester.enterText(addPerson, name);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.waitFor(find.text(name));
    }
    await tester.tapAndWait(find.text('Create Group').last);
    await tester.waitFor(find.text('Add expense'));
  });

  e2e('UC-1: logs, splits and edits an expense after a restart',
      (tester) async {
    await tester.openGroup();

    // Defaults: paid by me, split equally between everyone.
    await tester.tapAndWait(find.text('Add expense').last);
    await tester.enterText(find.byType(TextFormField).first, '300000');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'What was it for?'), 'Hotpot');
    await tester.tapAndWait(find.text('Save').last);
    await tester.waitFor(find.text('Hotpot'));
    expect(find.textContaining('300.000'), findsWidgets);

    // UC-1.4: shares sum exactly to the total.
    await tester.tapAndWait(find.text('Hotpot'));
    await tester.waitFor(find.text('Split breakdown'));
    expect(find.textContaining('100.000'), findsNWidgets(3));

    // UC-1.5: edit the entry from its detail screen.
    await tester.tapAndWait(find.byTooltip('Edit expense'));
    await tester.enterText(find.byType(TextFormField).first, '360000');
    await tester.tapAndWait(find.text('Save').last);
    await tester.waitFor(find.textContaining('120.000'));
  });

  e2e('UC-2 and UC-4: shows simplified debts and settles one', (tester) async {
    await tester.openGroup();

    await tester.tapAndWait(find.text('Settlements'));
    await tester.waitFor(find.text('Who pays whom'));
    expect(find.text('Settle'), findsNWidgets(2));

    await tester.tapAndWait(find.text('Settle').first);
    await tester.waitFor(find.text('Record settlement'));
    await tester.tapAndWait(find.text('Confirm paid'));
    await tester.waitFor(find.text('Settle'), count: 1);
    expect(find.text('No settlements yet'), findsNothing);
  });

  e2e('UC-1.5: deletes an expense by swiping it away', (tester) async {
    await tester.openGroup();

    await tester.waitFor(find.text('Hotpot'));
    await tester.fling(find.text('Hotpot'), const Offset(-600, 0), 2000);
    await tester.waitFor(find.text('Delete expense?'));
    await tester.tapAndWait(find.text('Delete').last);
    await tester.waitFor(find.text('Hotpot'), count: 0);
  });

  e2e('UC-6: language and theme apply without a restart', (tester) async {
    await tester.launch();
    await tester.tapAndWait(find.byTooltip('Settings'));
    await tester.tapAndWait(find.text('Tiếng Việt'));
    await tester.waitFor(find.text('English'));
    expect(find.text('Settings'), findsNothing);
    await tester.tapAndWait(find.text('English'));
    await tester.waitFor(find.text('Settings'));
    await tester.tapAndWait(find.text('Dark'));
    expect(
      Theme.of(tester.element(find.text('Settings'))).brightness,
      Brightness.dark,
    );
  });
}

extension on WidgetTester {
  /// Starts the app as a cold start would: on the group list. Each launch
  /// gets a fresh ProviderScope, and with it a fresh router at '/'. The web
  /// build has no Firebase, so there is no sign-in gate.
  Future<void> launch() async {
    app.main();
    await waitFor(find.byTooltip('Settings'));
  }

  /// Relaunches the app and opens the group created by the first test.
  Future<void> openGroup() async {
    await launch();
    await tapAndWait(find.textContaining('Da Lat trip'));
    await waitFor(find.text('Add expense'));
  }

  /// Pumps frames until [finder] matches [count] widgets (at least one when
  /// null). Unlike pumpAndSettle this tolerates endless animations, and the
  /// Drift web worker answers asynchronously, outside the fake clock.
  Future<void> waitFor(
    Finder finder, {
    int? count,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final end = DateTime.now().add(timeout);
    bool done() {
      final n = finder.evaluate().length;
      return count == null ? n > 0 : n == count;
    }

    while (!done()) {
      if (DateTime.now().isAfter(end)) {
        final onScreen = find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .whereType<String>()
            .toSet();
        throw TestFailure('Timed out waiting for $finder'
            '${count == null ? '' : ' (expected $count)'}\n'
            'Texts on screen: ${onScreen.join(' | ')}');
      }
      await pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapAndWait(Finder finder) async {
    await waitFor(finder);
    // Scroll only when needed: in a NestedScrollView, ensureVisible can park
    // the target under the pinned header, where the tap would land instead.
    final screen = Offset.zero & view.physicalSize / view.devicePixelRatio;
    if (!screen.contains(getCenter(finder.first))) {
      await ensureVisible(finder.first);
      await pump(const Duration(milliseconds: 300));
    }
    await tap(finder.first);
    for (var i = 0; i < 10; i++) {
      await pump(const Duration(milliseconds: 100));
    }
  }
}
