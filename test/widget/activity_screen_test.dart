import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/activity_entry.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/screens/activity/activity_screen.dart';

import '../helpers/mocks.dart';

void main() {
  final edit = ActivityEntry(
    id: 'a1',
    groupId: 'g1',
    actorUid: 'bob',
    action: ActivityAction.update,
    entityType: ActivityEntityType.expense,
    entityId: 'e1',
    before: const {
      'title': 'Hotpot',
      'amountCents': 30000000,
      'currencyCode': 'VND'
    },
    after: const {
      'title': 'Hotpot',
      'amountCents': 36000000,
      'currencyCode': 'VND'
    },
    clientTime: DateTime(2026, 10, 1, 9, 30),
    synced: false,
  );

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activityListProvider('g1').overrideWith((ref) => Stream.value([edit])),
        memberListProvider('g1').overrideWith((ref) => Stream.value(
            [testMember('m2', name: 'Linh').copyWith(linkedUid: 'bob')])),
        liveGroupProvider('g1')
            .overrideWith((ref) => Stream.value(testGroup())),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists changes with who made them and a not-synced mark (AC25)',
      (tester) async {
    await pump(tester, const ActivityScreen(groupId: 'g1'));

    expect(find.text('Linh edited “Hotpot”'), findsOneWidget);
    expect(find.byTooltip('Not synced yet'), findsOneWidget);
  });

  testWidgets(
      'shows an edit field by field, old → new, and offers no edit '
      'or delete (AC26, AC28)', (tester) async {
    await pump(
        tester, const ActivityDetailScreen(groupId: 'g1', activityId: 'a1'));

    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.textContaining('300.000 ₫'), findsOneWidget);
    expect(find.textContaining('360.000 ₫'), findsOneWidget);
    expect(find.text('Description'), findsNothing, reason: 'unchanged');
    expect(find.byType(IconButton), findsNothing);
  });
}
