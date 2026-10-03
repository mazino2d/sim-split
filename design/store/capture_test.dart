// Captures raw app screens for the Play Store screenshots.
//
//   python3 design/build.py   (runs this test, then frames the shots)
//
// Capture names must match the ids in design/shots.json.
//
// Not part of the CI test suite (it lives outside test/), so the analyzer
// does not treat it as a test.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/screens/expenses/expense_form_screen.dart';
import 'package:simsplit/presentation/screens/groups/group_detail_screen.dart';
import 'package:simsplit/presentation/screens/groups/group_list_screen.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(ByteData.view(File(f).readAsBytesSync().buffer)),
      );
    }
    await loader.load();
  }

  await load('BeVietnamPro', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      'assets/fonts/BeVietnamPro-$w.ttf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  await load('MaterialIcons', [
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

/// Sample trip, localized so EN and VI shots read naturally.
class _Sample {
  _Sample(this.locale);

  final String locale;
  bool get vi => locale == 'vi';

  final now = DateTime.now();
  DateTime daysAgo(int d) => DateTime(now.year, now.month, now.day - d, 12);

  late final members = [
    _member('k', 'Khôi', me: true),
    _member('l', 'Linh'),
    _member('m', 'Minh'),
    _member('a', 'An'),
  ];

  Member _member(String id, String name, {bool me = false}) => Member(
        id: id,
        groupId: 'g1',
        name: name,
        avatarColorValue: 0,
        isMe: me,
        createdAt: daysAgo(10),
      );

  late final trip = Group(
    id: 'g1',
    name: vi ? 'Đà Lạt cuối tuần' : 'Da Lat weekend',
    colorValue: 0,
    currencyCode: 'VND',
    createdAt: daysAgo(3),
    updatedAt: now,
  );
  late final lunch = Group(
    id: 'g2',
    name: vi ? 'Ăn trưa văn phòng' : 'Office lunches',
    colorValue: 0,
    currencyCode: 'VND',
    createdAt: daysAgo(30),
    updatedAt: now,
  );

  Expense _expense(String id, String title, int vnd, String payer,
      ExpenseCategory category, int day, List<String> who) {
    final cents = vnd * 100;
    final each = cents ~/ who.length;
    return Expense(
      id: id,
      groupId: 'g1',
      title: title,
      amountCents: cents,
      currencyCode: 'VND',
      paidByMemberId: payer,
      splitType: SplitType.equal,
      category: category,
      expenseDate: daysAgo(day),
      createdAt: daysAgo(day),
      updatedAt: daysAgo(day),
      splits: [
        for (final w in who)
          ExpenseSplit(
            id: '$id$w',
            expenseId: id,
            memberId: w,
            value: each,
            amountCents: each,
          ),
      ],
    );
  }

  late final expenses = [
    _expense('1', vi ? 'Cà phê bên hồ' : 'Lakeside coffee', 180000, 'a',
        ExpenseCategory.food, 0, ['k', 'l', 'a']),
    _expense('2', vi ? 'Vé vườn dâu' : 'Strawberry farm', 400000, 'k',
        ExpenseCategory.entertainment, 0, ['k', 'l', 'm', 'a']),
    _expense('3', vi ? 'Thuê xe máy' : 'Scooter rental', 600000, 'm',
        ExpenseCategory.transport, 1, ['k', 'l', 'm', 'a']),
    _expense('4', vi ? 'Lẩu tối' : 'Hotpot dinner', 960000, 'l',
        ExpenseCategory.food, 1, ['k', 'l', 'm', 'a']),
    _expense('5', vi ? 'Homestay 2 đêm' : 'Homestay, 2 nights', 2400000, 'k',
        ExpenseCategory.accommodation, 2, ['k', 'l', 'm', 'a']),
  ];

  late final summary = DebtSummary(
    groupId: 'g1',
    currencyCode: 'VND',
    balances: [
      MemberBalance(member: members[0], netAmountCents: 146500000),
      MemberBalance(member: members[1], netAmountCents: -17500000),
      MemberBalance(member: members[2], netAmountCents: -53500000),
      MemberBalance(member: members[3], netAmountCents: -75500000),
    ],
    suggestions: [
      Debt(
          from: members[3],
          to: members[0],
          amountCents: 75500000,
          currencyCode: 'VND'),
      Debt(
          from: members[2],
          to: members[0],
          amountCents: 53500000,
          currencyCode: 'VND'),
      Debt(
          from: members[1],
          to: members[0],
          amountCents: 17500000,
          currencyCode: 'VND'),
    ],
  );

  late final settlements = [
    Settlement(
      id: 's1',
      groupId: 'g1',
      fromMemberId: 'a',
      toMemberId: 'k',
      amountCents: 20000000,
      currencyCode: 'VND',
      settledAt: daysAgo(1),
      createdAt: daysAgo(1),
    ),
  ];

  late final lunchMe = Member(
    id: 'x',
    groupId: 'g2',
    name: 'Khôi',
    avatarColorValue: 0,
    isMe: true,
    createdAt: daysAgo(30),
  );

  List overrides() => [
        groupListProvider.overrideWith((ref) => Stream.value([trip, lunch])),
        groupDetailProvider('g1').overrideWith((ref) async => trip),
        memberListProvider('g1').overrideWith((ref) => Stream.value(members)),
        memberListProvider('g2').overrideWith(
          (ref) => Stream.value([
            lunchMe,
            for (final n in ['Hà', 'Tuấn'])
              Member(
                id: n,
                groupId: 'g2',
                name: n,
                avatarColorValue: 0,
                createdAt: daysAgo(30),
              ),
          ]),
        ),
        expenseListProvider('g1').overrideWith((ref) => Stream.value(expenses)),
        settlementListProvider('g1')
            .overrideWith((ref) => Stream.value(settlements)),
        debtSummaryProvider('g1', 'VND').overrideWith((ref) async => summary),
        debtSummaryProvider('g2', 'VND').overrideWith(
          (ref) async => DebtSummary(
            groupId: 'g2',
            currencyCode: 'VND',
            balances: [
              MemberBalance(member: lunchMe, netAmountCents: -9500000),
            ],
            suggestions: const [],
          ),
        ),
      ];
}

Future<void> _capture(
  WidgetTester tester, {
  required String locale,
  required String name,
  required Widget home,
  bool dark = false,
  Future<void> Function(WidgetTester tester)? act,
}) async {
  tester.view.physicalSize = const Size(1080, 1800);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _Sample(locale).overrides().cast(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (act != null) {
    await act(tester);
    await tester.pumpAndSettle();
  }
  // Hide the text cursor so captures are stable.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('captures/$locale/$name.png'),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
  });

  for (final locale in ['en', 'vi']) {
    final settle = locale == 'vi' ? 'Thanh toán' : 'Settlements';

    testWidgets('$locale 01 home', (t) async {
      await _capture(t,
          locale: locale, name: '01_home', home: const GroupListScreen());
    });

    testWidgets('$locale 02 add expense', (t) async {
      await _capture(
        t,
        locale: locale,
        name: '02_add_expense',
        home: const ExpenseFormScreen(groupId: 'g1'),
        act: (t) async {
          await t.enterText(find.byType(TextFormField).first, '450000');
          await t.tap(find.text('An').first);
          // Minh skipped this one: tap him in the "Split between" row.
          await t.tap(find.text('Minh').last);
        },
      );
    });

    testWidgets('$locale 03 settle up', (t) async {
      await _capture(
        t,
        locale: locale,
        name: '03_settle_up',
        home: const GroupDetailScreen(groupId: 'g1'),
        act: (t) async => t.tap(find.text(settle)),
      );
    });

    testWidgets('$locale 04 dark', (t) async {
      await _capture(
        t,
        locale: locale,
        name: '04_dark',
        dark: true,
        home: const GroupDetailScreen(groupId: 'g1'),
      );
    });
  }
}
