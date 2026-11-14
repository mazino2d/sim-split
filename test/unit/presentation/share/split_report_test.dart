import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/entities/split_report.dart';
import 'package:simsplit/domain/use_cases/settlements/calculate_debts.dart';
import 'package:simsplit/presentation/share/split_image.dart';
import 'package:simsplit/presentation/share/split_text.dart';

import '../../../helpers/mocks.dart';

// The split shared to a chat (#115).

final _an = testMember('an', name: 'An');
final _binh = testMember('binh', name: 'Bình');
final _chi = testMember('chi', name: 'Chi');

Expense _expense(String id, Member payer, int amount, Map<Member, int> shares,
        {int day = 1}) =>
    testExpense(id: id, paidBy: payer.id, amountCents: amount).copyWith(
      title: 'Expense $id',
      expenseDate: DateTime(2026, 11, day),
      splits: [
        for (final e in shares.entries)
          ExpenseSplit(
            id: '$id-${e.key.id}',
            expenseId: id,
            memberId: e.key.id,
            value: e.value,
            amountCents: e.value,
          ),
      ],
    );

SplitReport _report(List<Expense> expenses, {required SettlementMode mode}) {
  final members = [_an, _binh, _chi];
  final paid = <String, int>{};
  final share = <String, int>{};
  for (final e in expenses.where((e) => !e.isDeleted)) {
    paid[e.paidByMemberId] = (paid[e.paidByMemberId] ?? 0) + e.amountCents;
    for (final s in e.splits) {
      share[s.memberId] = (share[s.memberId] ?? 0) + s.amountCents;
    }
  }
  final balances = [
    for (final m in members)
      MemberBalance(
        member: m,
        netAmountCents: (paid[m.id] ?? 0) - (share[m.id] ?? 0),
        paidCents: paid[m.id] ?? 0,
        shareCents: share[m.id] ?? 0,
      ),
  ];
  return buildSplitReport(
    group: testGroup().copyWith(name: 'Đà Lạt', emoji: '🏕️'),
    expenses: expenses,
    summary: DebtSummary(
      groupId: 'g1',
      currencyCode: 'VND',
      balances: balances,
      suggestions: mode == SettlementMode.hub
          ? hubDebts(balances: balances, collector: _an, currencyCode: 'VND')
          : const [],
      mode: mode,
      collector: mode == SettlementMode.hub ? _an : null,
    ),
  );
}

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // A preview (SPLIT_PREVIEW_DIR) uses the real font, not the test font.
    if (Platform.environment['SPLIT_PREVIEW_DIR'] != null) {
      final loader = FontLoader('BeVietnamPro');
      for (final w in ['Regular', 'Bold']) {
        final bytes =
            File('assets/fonts/BeVietnamPro-$w.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
  });

  final expenses = [
    _expense('2', _binh, 3000000, {_an: 1000000, _binh: 1000000, _chi: 1000000},
        day: 2),
    _expense('1', _an, 16500000, {_an: 5500000, _binh: 5500000, _chi: 5500000}),
    _expense('3', _chi, 900000, {_an: 450000, _chi: 450000}, day: 3)
        .copyWith(isDeleted: true),
  ];

  test('rows are the live expenses in date order', () {
    final r = _report(expenses, mode: SettlementMode.hub);
    expect(r.rows.map((row) => row.title), ['Expense 1', 'Expense 2']);
    expect(
        r.rows.first.shares, {'an': 5500000, 'binh': 5500000, 'chi': 5500000});
    expect(r.totalCents, 19500000);
  });

  test('in hub mode each member sends to or gets back from the collector', () {
    final r = _report(expenses, mode: SettlementMode.hub);
    // An paid 165.000, share 65.000: overpaid 100.000.
    expect(r.toCollector(_binh), 6500000 - 3000000);
    expect(r.toCollector(_chi), 6500000);
    expect(r.toCollector(_an), 0);
    final money = r.collectorMoney;
    expect(money.keeps, money.collects - money.refunds);
    expect(money.keeps, 10000000);
  });

  test('the text lists shares and who sends what to the collector', () {
    final text =
        splitReportText(_report(expenses, mode: SettlementMode.hub), l10n);
    expect(text, contains('🏕️ Đà Lạt: expense split'));
    expect(text, contains('Bình: share 65.000 đ, paid 30.000 đ'));
    expect(text, contains('Send to An:'));
    expect(text, contains('  Chi: 65.000 đ'));
    expect(text, isNot(contains('₫')));
  });

  testWidgets('renders a summary card and the expense pages', (tester) async {
    final r = _report(expenses, mode: SettlementMode.hub);
    final images = (await tester.runAsync(() => renderSplitImages(r, l10n)))!;
    expect(images, hasLength(2));
    final preview = Platform.environment['SPLIT_PREVIEW_DIR'];
    for (final (i, png) in images.indexed) {
      final codec =
          (await tester.runAsync(() => ui.instantiateImageCodec(png)))!;
      final frame = (await tester.runAsync(codec.getNextFrame))!;
      expect(frame.image.width, greaterThanOrEqualTo(1080));
      if (preview != null) File('$preview/split-$i.png').writeAsBytesSync(png);
    }
  });

  testWidgets('many expenses and members are split into readable images',
      (tester) async {
    final many = [
      for (var i = 0; i < 31; i++)
        _expense('$i', _an, 300, {_an: 100, _binh: 100, _chi: 100}),
    ];
    final r = _report(many, mode: SettlementMode.simplified);
    final images = (await tester.runAsync(() => renderSplitImages(r, l10n)))!;
    // The summary, then 31 rows on two pages of at most 30.
    expect(images, hasLength(3));
  });
}
