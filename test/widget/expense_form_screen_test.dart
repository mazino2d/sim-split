import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/expenses/add_expense.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/screens/expenses/expense_form_screen.dart';

import '../helpers/mocks.dart';

class _MockAddExpense extends Mock implements AddExpense {}

void main() {
  setUpAll(() {
    registerFallbackValue(const AddExpenseParams(
      groupId: 'g1',
      title: 't',
      amountCents: 1,
      currencyCode: 'VND',
      paidByMemberId: 'a',
      splitType: SplitType.equal,
      splitInputs: [],
    ));
  });

  final members = [
    testMember('a', name: 'An'),
    testMember('b', name: 'Binh'),
    testMember('c', name: 'Chi'),
  ];

  Future<_MockAddExpense> pump(
    WidgetTester tester, {
    List<Expense> expenses = const [],
    Widget form = const ExpenseFormScreen(groupId: 'g1'),
  }) async {
    final addExpense = _MockAddExpense();
    when(() => addExpense(any())).thenAnswer(
      (_) async => right<Failure, Expense>(testExpense()),
    );
    final router = GoRouter(
      initialLocation: '/add',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(),
          routes: [
            GoRoute(
              path: 'add',
              builder: (_, __) => form,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          addExpenseProvider.overrideWithValue(addExpense),
          groupDetailProvider('g1').overrideWith((ref) async => testGroup()),
          memberListProvider('g1').overrideWith((ref) => Stream.value(members)),
          expenseListProvider('g1')
              .overrideWith((ref) => Stream.value(expenses)),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return addExpense;
  }

  AddExpenseParams savedParams(_MockAddExpense addExpense) =>
      verify(() => addExpense(captureAny())).captured.single
          as AddExpenseParams;

  testWidgets('groups thousands in VND amounts while typing', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextFormField).first, '1250000');
    await tester.pump();
    expect(find.text('1.250.000'), findsOneWidget);
  });

  testWidgets(
      'saves an equal split among only the selected participants with a '
      'category title when no description is entered', (tester) async {
    final addExpense = await pump(tester);

    await tester.enterText(find.byType(TextFormField).first, '300000');
    // Second "Chi" is in the "Split between" row; deselect her.
    await tester.tap(find.text('Chi').last);
    await tester.tap(find.text('Transport'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final params = savedParams(addExpense);
    expect(params.amountCents, 30000000);
    expect(params.title, 'Transport');
    expect(params.category, ExpenseCategory.transport);
    expect(params.splitType, SplitType.equal);
    expect(params.splitInputs.map((i) => i.memberId), ['a', 'b']);
  });

  testWidgets('defaults the payer to whoever paid the most recent expense',
      (tester) async {
    final addExpense = await pump(
      tester,
      expenses: [testExpense(paidBy: 'c')],
    );

    await tester.enterText(find.byType(TextFormField).first, '90000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedParams(addExpense).paidByMemberId, 'c');
  });

  testWidgets('refuses to save when nobody is in the split', (tester) async {
    final addExpense = await pump(tester);

    await tester.enterText(find.byType(TextFormField).first, '90000');
    for (final name in ['An', 'Binh', 'Chi']) {
      await tester.tap(find.text(name).last);
    }
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verifyNever(() => addExpense(any()));
    expect(find.text('Add at least one participant'), findsOneWidget);
  });

  testWidgets(
      'opening an expense to name it focuses the description and selects '
      'the auto-filled title', (tester) async {
    final expense = testExpense(
      paidBy: 'a',
      splits: [
        for (final id in ['a', 'b'])
          ExpenseSplit(
            id: 's$id',
            expenseId: 'e1',
            memberId: id,
            value: 5000,
            amountCents: 5000,
          ),
      ],
    ).copyWith(title: 'Transport', category: ExpenseCategory.transport);

    await pump(
      tester,
      expenses: [expense],
      form: const ExpenseFormScreen(
        groupId: 'g1',
        editExpenseId: 'e1',
        focusTitle: true,
      ),
    );

    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Transport'),
    );
    expect(field.focusNode!.hasFocus, isTrue);
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 9),
    );
  });
}
