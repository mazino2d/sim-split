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
    bool archived = false,
    List<Member>? groupMembers,
  }) async {
    // Tall enough to lay out every card and the history without scrolling.
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupDetailProvider('g1').overrideWith(
              (ref) async => testGroup().copyWith(isArchived: archived)),
          memberListProvider('g1')
              .overrideWith((ref) => Stream.value(groupMembers ?? members)),
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
      balances: [
        MemberBalance(member: members[0], netAmountCents: 5000000),
        MemberBalance(member: members[1], netAmountCents: -5000000),
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

  testWidgets(
      'each balance shows share, paid and what is left to settle, '
      'with the trip total (#110)', (tester) async {
    await pumpSettlementsTab(
      tester,
      settlements: const [],
      balances: [
        MemberBalance(
            member: members[0],
            netAmountCents: 70000000,
            paidCents: 200000000,
            shareCents: 120000000,
            settledCents: -10000000),
        MemberBalance(
            member: members[1],
            netAmountCents: -70000000,
            paidCents: 40000000,
            shareCents: 120000000,
            settledCents: 10000000),
      ],
    );

    expect(find.text('Share'), findsNWidgets(2));
    expect(find.text('Paid'), findsNWidgets(2));
    expect(find.text('Settled'), findsNWidgets(2));
    expect(find.text('To settle'), findsNWidgets(2));
    expect(find.text(formatMoney(120000000, 'VND')), findsNWidgets(2));
    expect(find.text(formatMoney(200000000, 'VND')), findsOneWidget);
    // ↓ waits to be paid back, ↑ still pays.
    expect(find.text(formatMoney(70000000, 'VND')), findsNWidgets(2));
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.text('Total ${formatMoney(240000000, 'VND')}'), findsOneWidget);
  });

  testWidgets('a balance without settlements hides the settled line',
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

    expect(find.text('Settled'), findsNothing);
    expect(find.text('Total ${formatMoney(240000000, 'VND')}'), findsOneWidget);
  });

  group('one card per member (who pays whom and balances)', () {
    final me = testMember('m', name: 'Khoi').copyWith(isMe: true);
    final linh = testMember('l', name: 'Linh');
    final nam = testMember('n', name: 'Nam');
    final lam = testMember('lam', name: 'Lam');
    final ha = testMember('h', name: 'Ha');
    final people = [nam, linh, ha, lam, me];
    Debt debt(Member from, Member to, int cents) =>
        Debt(from: from, to: to, amountCents: cents, currencyCode: 'VND');

    Future<void> pumpHub(WidgetTester tester, {bool archived = false}) =>
        pumpSettlementsTab(
          tester,
          settlements: const [],
          groupMembers: people,
          mode: SettlementMode.hub,
          collector: linh,
          archived: archived,
          balances: [
            MemberBalance(
                member: nam, netAmountCents: -55833300, shareCents: 55833300),
            MemberBalance(
                member: linh,
                netAmountCents: 9166700,
                shareCents: 55833300,
                paidCents: 65000000),
            MemberBalance(
                member: ha,
                netAmountCents: 0,
                shareCents: 1000000,
                paidCents: 1000000),
            MemberBalance(
                member: lam,
                netAmountCents: -5833300,
                shareCents: 55833300,
                paidCents: 50000000),
            MemberBalance(
                member: me,
                netAmountCents: 52500000,
                shareCents: 52500000,
                paidCents: 105000000),
          ],
          suggestions: [
            debt(nam, linh, 55833300),
            debt(lam, linh, 5833300),
            debt(linh, me, 52500000),
          ],
        );

    testWidgets('orders you, payers, the collector, receivers, then settled',
        (tester) async {
      await pumpHub(tester);
      double top(String name) => tester.getTopLeft(find.text(name).first).dy;
      final order = [
        top('You'),
        top('Nam'),
        top('Lam'),
        top('Linh · collector'),
        top('Ha'),
      ];
      expect(order, [...order]..sort());
    });

    testWidgets('shows transfers with Settle, the collector and who waits',
        (tester) async {
      await pumpHub(tester);
      expect(find.text('Settle'), findsNWidgets(3));
      expect(
          find.text('Collects ${formatMoney(61666600, 'VND')} · '
              'pays back ${formatMoney(52500000, 'VND')}'),
          findsOneWidget);
      expect(find.text('Waiting for Linh'), findsOneWidget);
      // Ha is even: all figures, no transfer.
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('an archived group shows no Settle', (tester) async {
      await pumpHub(tester, archived: true);
      expect(find.text('Settle'), findsNothing);
      expect(find.text('Waiting for Linh'), findsOneWidget);
    });

    testWidgets('fewest transfers can give one member two transfers',
        (tester) async {
      await pumpSettlementsTab(
        tester,
        settlements: const [],
        groupMembers: [nam, linh, me],
        balances: [
          MemberBalance(member: nam, netAmountCents: -3000000),
          MemberBalance(member: linh, netAmountCents: 1000000),
          MemberBalance(member: me, netAmountCents: 2000000),
        ],
        suggestions: [debt(nam, me, 2000000), debt(nam, linh, 1000000)],
      );
      expect(find.text('Settle'), findsNWidgets(2));
      expect(find.text('Waiting for Nam'), findsNWidgets(2));
    });
  });
}
