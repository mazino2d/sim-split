import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/widgets/settlements/settlement_mode_sheet.dart';

import '../helpers/mocks.dart';

void main() {
  testWidgets('Done closes the settlement mode sheet', (tester) async {
    final group = testGroup().copyWith(settlementMode: SettlementMode.hub);
    final an = testMember('m1', name: 'An');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        liveGroupProvider('g1').overrideWith((ref) => Stream.value(group)),
        memberListProvider('g1').overrideWith((ref) => Stream.value([an])),
        debtSummaryProvider('g1', 'VND').overrideWith(
          (ref) async => DebtSummary(
            groupId: 'g1',
            currencyCode: 'VND',
            balances: const [],
            suggestions: const [],
            mode: SettlementMode.hub,
            collector: an,
          ),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSettlementModeSheet(context, 'g1'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('How to settle up'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('How to settle up'), findsNothing);
  });
}
