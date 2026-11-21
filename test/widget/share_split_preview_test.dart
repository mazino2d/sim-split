import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/screens/share/share_split_preview_screen.dart';

import '../helpers/mocks.dart';

void main() {
  Future<void> pump(WidgetTester tester, {bool fail = false}) async {
    final an = testMember('m1', name: 'An');
    final app = ProviderScope(
      overrides: [
        groupDetailProvider('g1').overrideWith(
            (ref) async => fail ? throw StateError('offline') : testGroup()),
        expenseListProvider('g1')
            .overrideWith((ref) => Stream.value([testExpense()])),
        debtSummaryProvider('g1', 'VND').overrideWith(
          (ref) async => DebtSummary(
            groupId: 'g1',
            currencyCode: 'VND',
            balances: [
              MemberBalance(
                  member: an,
                  netAmountCents: 0,
                  shareCents: 100,
                  paidCents: 100),
            ],
            suggestions: const [],
          ),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ShareSplitPreviewScreen(groupId: 'g1'),
      ),
    );
    // Drawing the image needs real async work, outside the fake clock.
    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  testWidgets('shows the image that will be sent, with Share', (tester) async {
    await pump(tester);
    expect(find.byType(Image), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Share'), findsOneWidget);
  });

  testWidgets('offers Retry when the image cannot be drawn', (tester) async {
    await pump(tester, fail: true);
    expect(find.text("Couldn't share the split"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
