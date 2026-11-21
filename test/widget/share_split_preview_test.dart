import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/platform/image_saver.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/screens/share/share_split_preview_screen.dart';

import '../helpers/mocks.dart';

void main() {
  late List<String> saved;
  late List<String> shared;

  Future<void> pump(WidgetTester tester, {bool fail = false}) async {
    saved = [];
    shared = [];
    final an = testMember('m1', name: 'An');
    final app = ProviderScope(
      overrides: [
        splitImageSaverProvider.overrideWithValue((images) async {
          saved.addAll(images.map((i) => i.name));
          return ImageSaveResult.saved;
        }),
        splitImageSharerProvider.overrideWithValue((subject, images) async {
          shared.addAll(images.map((i) => i.name));
        }),
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

  testWidgets('shows each image on its own page, to swipe through',
      (tester) async {
    await pump(tester);
    expect(find.text('1/3 · Summary'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2/3 · Who pays whom'), findsOneWidget);
  });

  testWidgets('saves and shares every image under a timed file name',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(shared, hasLength(3));
    expect(shared.first, matches(RegExp(r'^simsplit-.*-\d{8}-\d{4}-1\.png$')));
    await tester.tap(find.text('Save image'));
    await tester.pumpAndSettle();
    expect(saved, shared);
    expect(find.text('Saved to Photos'), findsOneWidget);
  });

  testWidgets('offers Retry when the image cannot be drawn', (tester) async {
    await pump(tester, fail: true);
    expect(find.text("Couldn't share the split"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
