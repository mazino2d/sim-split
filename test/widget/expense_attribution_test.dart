import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/screens/expenses/expense_detail_screen.dart';
import 'package:simsplit/presentation/widgets/common/unsynced_mark.dart';
import 'package:simsplit/presentation/widgets/expenses/expense_list_tile.dart';

import '../helpers/mocks.dart';

Widget _app(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

void main() {
  final members = [
    testMember('m1', name: 'Khoi').copyWith(linkedUid: 'alice', isMe: true),
    testMember('m2', name: 'Linh').copyWith(linkedUid: 'bob'),
  ];

  Future<void> pumpDetail(WidgetTester tester, Expense expense) async {
    await tester.pumpWidget(_app(
      const ExpenseDetailScreen(groupId: 'g1', expenseId: 'e1'),
      overrides: [
        groupDetailProvider('g1').overrideWith((ref) async => testGroup()),
        memberListProvider('g1').overrideWith((ref) => Stream.value(members)),
        expenseListProvider('g1')
            .overrideWith((ref) => Stream.value([expense])),
      ],
    ));
    await tester.pumpAndSettle();
  }

  group('expense detail (AC18)', () {
    testWidgets('names who added the expense', (tester) async {
      await pumpDetail(tester, testExpense().copyWith(createdBy: 'bob'));

      expect(find.text('Added by Linh'), findsOneWidget);
      expect(find.textContaining('Edited by'), findsNothing);
    });

    testWidgets('names who edited it and when', (tester) async {
      final expense = testExpense().copyWith(
        createdBy: 'bob',
        updatedBy: 'alice',
        updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      await pumpDetail(tester, expense);

      expect(find.text('Edited by Khoi (me) · 5 min ago'), findsOneWidget);
    });

    testWidgets('says nothing for expenses added while signed out',
        (tester) async {
      await pumpDetail(tester, testExpense());

      expect(find.textContaining('Added by'), findsNothing);
    });
  });

  group('expense list tile (AC16)', () {
    Future<void> pumpTile(WidgetTester tester, {required bool unsynced}) =>
        tester.pumpWidget(_app(Scaffold(
          body: ExpenseListTile(
            expense: testExpense(),
            members: const <Member>[],
            unsynced: unsynced,
          ),
        )));

    testWidgets('marks an expense that has not synced yet', (tester) async {
      await pumpTile(tester, unsynced: true);

      expect(find.byType(UnsyncedMark), findsOneWidget);
      expect(find.byTooltip('Not synced yet'), findsOneWidget);
    });

    testWidgets('shows no mark once synced', (tester) async {
      await pumpTile(tester, unsynced: false);

      expect(find.byType(UnsyncedMark), findsNothing);
    });
  });
}
