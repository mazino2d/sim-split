import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/screens/groups/group_list_screen.dart';

import '../helpers/mocks.dart';

// Archived groups leave the main list and wait under "Archived (n)" (#117).

void main() {
  testWidgets('archived groups are folded away under Archived', (tester) async {
    final active = testGroup(id: 'g1').copyWith(name: 'Da Lat');
    final archived =
        testGroup(id: 'g2').copyWith(name: 'Vung Tau', isArchived: true);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        groupListProvider
            .overrideWith((ref) => Stream.value([active, archived])),
        for (final id in ['g1', 'g2'])
          memberListProvider(id)
              .overrideWith((ref) => Stream.value(const <Member>[])),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GroupListScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Da Lat'), findsOneWidget);
    expect(find.text('Vung Tau'), findsNothing);
    expect(find.text('Archived (1)'), findsOneWidget);

    await tester.tap(find.text('Archived (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Vung Tau'), findsOneWidget);
  });
}
