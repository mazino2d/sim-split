import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:simsplit/main.dart' as app;

/// End-to-end journey through the real app: real Drift database, real
/// router, real providers, and Firebase Auth and Firestore emulators (run
/// with --dart-define=FIREBASE_EMULATOR_HOST=localhost). Covers the core and
/// supporting use cases in docs/product/use-cases.md on a fresh install.
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

  e2e('UC-7.1: a fresh install opens on sign-in', (tester) async {
    app.main();
    await tester.waitFor(find.text('Continue with Google'));
    await tester.signIn();
    await tester.waitFor(find.text('No groups yet'));
  });

  e2e('UC-3: sets up a group with members', (tester) async {
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

  e2e('UC-7.5: pushes the group to the account, then signs out',
      (tester) async {
    await tester.launch();
    // The earlier tests' changes have been pushed by now.
    final groups = await FirebaseFirestore.instance
        .collection('groups')
        .where('memberUids',
            arrayContains: FirebaseAuth.instance.currentUser!.uid)
        .get();
    expect(groups.docs.map((d) => d.data()['name']), ['Da Lat trip']);

    await tester.tapAndWait(find.byTooltip('Settings'));
    await tester.tapAndWait(find.text('Sign out'));
    await tester.tapAndWait(find.text('Sign out').last);
    await tester.waitFor(find.text('Continue with Google'));
  });

  e2e('UC-7.2: signing in again pulls the account\'s groups back',
      (tester) async {
    app.main();
    await tester.waitFor(find.text('Continue with Google'));
    await tester.signIn();
    // Sign-out left nothing on the device: this comes from Firestore.
    await tester.openGroupWhenPulled();
    // The deleted expense stays deleted; the recorded settlement is back.
    expect(find.text('Hotpot'), findsNothing);
    await tester.tapAndWait(find.text('Settlements'));
    await tester.waitFor(find.text('Who pays whom'));
    expect(find.text('No settlements yet'), findsNothing);
  });

  e2e('UC-8: a friend joins with the invite link and claims their name',
      (tester) async {
    await tester.openGroup();
    await tester.tapAndWait(find.byTooltip('Share group'));
    final mine = FirebaseFirestore.instance.collection('groups').where(
        'memberUids',
        arrayContains: FirebaseAuth.instance.currentUser!.uid);
    await tester.waitUntil(() async =>
        (await mine.get()).docs.single.data()['inviteToken'] != null);
    final groupDoc = (await mine.get()).docs.single;
    final group = groupDoc.reference;
    final token = groupDoc.data()['inviteToken'] as String;

    // Linh opens the link on her own device.
    await tester.signOutFromSettings();
    await tester.signIn(_e2eFriend);
    tester.goTo('/join/$token');
    await tester.waitUntil(() async {
      try {
        final uids = (await group.get()).data()!['memberUids'] as List;
        return uids.contains(FirebaseAuth.instance.currentUser!.uid);
      } on FirebaseException {
        return false;
      }
    });
    await tester.waitFor(find.text('Which one is you?'));
    expect(find.text('Khoi'), findsNothing, reason: 'claimed by Khoi');
    await tester.tapAndWait(find.text('Linh'));
    await tester.waitFor(find.text('Add expense'));

    final linh = (await group
            .collection('members')
            .where('name', isEqualTo: 'Linh')
            .get())
        .docs
        .single
        .reference;
    await tester.waitUntil(() async =>
        (await linh.get()).data()!['linkedUid'] ==
        FirebaseAuth.instance.currentUser!.uid);
  });

  e2e('UC-8.4: leaves the group', (tester) async {
    await tester.openGroup();
    await tester.tapAndWait(find.byTooltip('More'));
    await tester.tapAndWait(find.text('Leave group'));
    await tester.tapAndWait(find.text('Leave').last);
    await tester.waitFor(find.text('No groups yet'));
  });

  e2e('UC-7.6: deletes the account from inside the app', (tester) async {
    await tester.launch();

    await tester.tapAndWait(find.byTooltip('Settings'));
    await tester.tapAndWait(find.text('Delete account'));
    await tester.tapAndWait(find.text('Delete').last);
    await tester.waitFor(find.text('Continue with Google'));
    expect(FirebaseAuth.instance.currentUser, isNull);
  });
}

/// The Google account the journey signs in with. The Auth emulator accepts
/// these claims as an unsigned Google ID token.
const _e2eUser = {
  'sub': 'e2e-khoi',
  'email': 'khoi@example.com',
  'email_verified': true,
  'name': 'Khoi',
};

/// A friend who joins the group with an invite link (UC-8).
const _e2eFriend = {
  'sub': 'e2e-linh',
  'email': 'linh@example.com',
  'email_verified': true,
  'name': 'Linh',
};

extension on WidgetTester {
  /// Starts the app as a cold start would, signed in: on the group list.
  /// Each launch gets a fresh ProviderScope, and with it a fresh router at
  /// '/'. The session survives relaunches, as it does in the browser.
  Future<void> launch() async {
    app.main();
    await waitFor(find.byTooltip('Settings'));
  }

  /// Signs in as [_e2eUser] where the sign-in screen's Google popup would.
  /// The router leaves the sign-in screen on its own.
  Future<void> signIn([Map<String, Object> user = _e2eUser]) async {
    await FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: jsonEncode(user)),
    );
    await waitFor(find.byTooltip('Settings'));
  }

  /// Signs out the way a user does, which also clears the device.
  Future<void> signOutFromSettings() async {
    goTo('/settings');
    await tapAndWait(find.text('Sign out'));
    await tapAndWait(find.text('Sign out').last);
    await waitFor(find.text('Continue with Google'));
  }

  /// Opens [location] as a link would.
  void goTo(String location) =>
      GoRouter.of(element(find.byType(Scaffold).first)).go(location);

  /// Pumps frames until [condition] holds.
  Future<void> waitUntil(
    Future<bool> Function() condition, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!await condition()) {
      if (DateTime.now().isAfter(end)) {
        throw TestFailure('Timed out waiting for a condition');
      }
      await pump(const Duration(milliseconds: 200));
    }
  }

  /// Relaunches the app and opens the group created by the first test.
  Future<void> openGroup() async {
    await launch();
    await tapAndWait(find.textContaining('Da Lat trip'));
    await waitFor(find.text('Add expense'));
  }

  /// Opens the group created by the first test once sync has pulled it.
  Future<void> openGroupWhenPulled() async {
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
