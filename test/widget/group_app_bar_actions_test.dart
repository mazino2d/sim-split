import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/widgets/groups/group_app_bar_actions.dart';

import '../helpers/mocks.dart';

void main() {
  Future<void> pump(WidgetTester tester, Group group,
      {String uid = 'alice', bool synced = true}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authAvailableProvider.overrideWithValue(synced),
        currentUserProvider
            .overrideWith((ref) => Stream.value(AuthUser(uid: uid))),
        liveGroupProvider('g1').overrideWith((ref) => Stream.value(group)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            appBar: AppBar(actions: const [GroupAppBarActions(groupId: 'g1')])),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('keeps only Share and More in the app bar', (tester) async {
    await pump(
        tester, testGroup().copyWith(ownerUid: 'alice', memberUids: ['alice']));

    expect(find.byType(IconButton), findsNWidgets(2));
    expect(find.byTooltip('Share group'), findsOneWidget);
    expect(find.byTooltip('Activity'), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Edit Group'), findsOneWidget);
    // No link to reset yet, nobody else to leave to.
    expect(find.text('Reset invite link'), findsNothing);
    expect(find.text('Leave group'), findsNothing);
  });

  testWidgets('offers only editing without accounts', (tester) async {
    await pump(tester, testGroup(), synced: false);

    expect(find.byTooltip('Share group'), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Group'), findsOneWidget);
    expect(find.text('Activity'), findsNothing);
  });

  testWidgets('lets the owner reset an existing link', (tester) async {
    await pump(
        tester,
        testGroup().copyWith(
            ownerUid: 'alice', memberUids: ['alice'], inviteToken: 't'));

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Reset invite link'), findsOneWidget);
    expect(find.text('Leave group'), findsNothing);
  });

  testWidgets('lets a member leave when others are in the group',
      (tester) async {
    await pump(
        tester,
        testGroup().copyWith(
            ownerUid: 'alice', memberUids: ['alice', 'bob'], inviteToken: 't'),
        uid: 'bob');

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Leave group'), findsOneWidget);
    expect(find.text('Reset invite link'), findsNothing);
  });
}
