import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/screens/groups/group_detail_screen.dart';

import '../helpers/mocks.dart';

void main() {
  final members = [
    testMember('a', name: 'An'),
    testMember('b', name: 'Binh'),
  ];

  Settlement settlement({String id = 's1', String? note}) => Settlement(
        id: id,
        groupId: 'g1',
        fromMemberId: 'b',
        toMemberId: 'a',
        amountCents: 5000000,
        currencyCode: 'VND',
        note: note,
        settledAt: DateTime(2026, 3, 14),
        createdAt: DateTime(2026, 3, 14),
      );

  Future<void> pumpSettlementsTab(
    WidgetTester tester, {
    required List<Settlement> settlements,
    List<Debt> suggestions = const [],
    List<MemberBalance> balances = const [],
    SettlementMode mode = SettlementMode.simplified,
    Member? collector,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupDetailProvider('g1').overrideWith((ref) async => testGroup()),
          memberListProvider('g1').overrideWith((ref) => Stream.value(members)),
          expenseListProvider('g1')
              .overrideWith((ref) => Stream.value(const <Expense>[])),
          settlementListProvider('g1')
              .overrideWith((ref) => Stream.value(settlements)),
          debtSummaryProvider('g1', 'VND').overrideWith(
            (ref) async => DebtSummary(
              groupId: 'g1',
              currencyCode: 'VND',
              balances: balances,
              suggestions: suggestions,
              mode: mode,
              collector: collector,
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GroupDetailScreen(groupId: 'g1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settlements'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows recorded settlements with payer, payee, date and note',
      (tester) async {
    await pumpSettlementsTab(
      tester,
      settlements: [settlement(note: 'Taxi')],
    );

    expect(find.text('All settled up!'), findsOneWidget);
    expect(find.text('Settlement history'), findsOneWidget);
    expect(find.text('Binh paid An'), findsOneWidget);
    expect(find.text('14 Mar 2026 · Taxi'), findsOneWidget);
  });

  testWidgets('shows an empty message when nothing has been settled yet',
      (tester) async {
    await pumpSettlementsTab(
      tester,
      settlements: const [],
      suggestions: [
        Debt(
          from: members[1],
          to: members[0],
          amountCents: 5000000,
          currencyCode: 'VND',
        ),
      ],
    );

    expect(find.text('Settle'), findsOneWidget);
    expect(find.text('No settlements yet'), findsOneWidget);
  });

  testWidgets('asks for confirmation before deleting a settlement',
      (tester) async {
    await pumpSettlementsTab(tester, settlements: [settlement()]);

    await tester.drag(find.text('Binh paid An'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Delete settlement?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Binh paid An'), findsOneWidget);
  });

  group('settlement mode (#116)', () {
    testWidgets('names the collector in hub mode', (tester) async {
      await pumpSettlementsTab(
        tester,
        settlements: const [],
        mode: SettlementMode.hub,
        collector: members[0],
        suggestions: [
          Debt(
            from: members[1],
            to: members[0],
            amountCents: 5000000,
            currencyCode: 'VND',
          ),
        ],
      );
      expect(find.text('Settling through An'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('asks for a collector instead of claiming all is settled',
        (tester) async {
      await pumpSettlementsTab(
        tester,
        settlements: const [],
        mode: SettlementMode.hub,
        balances: [
          MemberBalance(member: members[0], netAmountCents: 5000000),
          MemberBalance(member: members[1], netAmountCents: -5000000),
        ],
      );
      expect(find.text('Pick who collects the money to see who pays whom'),
          findsOneWidget);
      expect(find.text('All settled up!'), findsNothing);
    });

    testWidgets('says fewest transfers otherwise', (tester) async {
      await pumpSettlementsTab(tester, settlements: const []);
      expect(find.text('Fewest transfers'), findsOneWidget);
    });
  });

  testWidgets('each balance shows paid and share, with the trip total (#110)',
      (tester) async {
    await pumpSettlementsTab(
      tester,
      settlements: const [],
      balances: [
        MemberBalance(
            member: members[0],
            netAmountCents: 80000000,
            paidCents: 200000000,
            shareCents: 120000000),
        MemberBalance(
            member: members[1],
            netAmountCents: -80000000,
            paidCents: 40000000,
            shareCents: 120000000),
      ],
    );

    expect(
        find.text('Paid ${formatMoney(200000000, 'VND')} · '
            'Share ${formatMoney(120000000, 'VND')}'),
        findsOneWidget);
    expect(find.text('Total ${formatMoney(240000000, 'VND')}'), findsOneWidget);
  });
}
