import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/screens/settlements/settlement_form_screen.dart';

void main() {
  final now = DateTime(2026);
  Group group(String currency) => Group(
        id: 'g1',
        name: 'Trip',
        colorValue: 0xFF1976D2,
        currencyCode: currency,
        createdAt: now,
        updatedAt: now,
      );
  final members = [
    Member(
      id: 'a',
      groupId: 'g1',
      name: 'An',
      avatarColorValue: 0xFF1976D2,
      createdAt: now,
    ),
    Member(
      id: 'b',
      groupId: 'g1',
      name: 'Binh',
      avatarColorValue: 0xFF1976D2,
      createdAt: now,
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required String currency,
    String? from,
    String? to,
    int? amountCents,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupDetailProvider('g1')
              .overrideWith((ref) async => group(currency)),
          memberListProvider('g1').overrideWith((ref) => Stream.value(members)),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettlementFormScreen(
            groupId: 'g1',
            fromMemberId: from,
            toMemberId: to,
            suggestedAmountCents: amountCents,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows an error instead of crashing when members are missing',
      (tester) async {
    await pump(tester, currency: 'USD');
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.settlementDetailsMissing), findsOneWidget);
    expect(find.text(l10n.confirmPaid), findsNothing);
  });

  testWidgets('prefills exact cents for decimal currencies', (tester) async {
    await pump(
      tester,
      currency: 'USD',
      from: 'a',
      to: 'b',
      amountCents: 3333,
    );
    expect(find.text('33.33'), findsOneWidget);
    expect(find.text('An owes Binh'), findsOneWidget);
  });

  testWidgets('prefills whole units for zero-decimal currencies',
      (tester) async {
    await pump(
      tester,
      currency: 'VND',
      from: 'a',
      to: 'b',
      amountCents: 10000000,
    );
    expect(find.text('100.000'), findsOneWidget);
  });
}
