import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/widgets/expenses/expense_list_tile.dart';
import 'package:simsplit/presentation/widgets/groups/group_card.dart';
import 'package:simsplit/presentation/widgets/settlements/debt_card.dart';
import 'package:simsplit/presentation/widgets/settlements/settlement_list_tile.dart';

import '../helpers/mocks.dart';

// Long titles and names on a 360 dp phone wrap to two lines instead of being
// cut after a few words, without overflowing (#111). The test font draws
// every glyph a full em wide, about twice a real font, so text that wraps
// here fits on fewer lines on a device.

const _title = 'Ăn tối hải sản Vũng Tàu cùng cả nhóm';
const _groupName = 'Du lịch Đà Lạt cuối tuần cùng đồng nghiệp';
const _payer = 'Nguyễn Thị Phương Thảo';
const _receiver = 'Trần Hoàng Minh Khôi';
// 1.250.000 ₫ and 12.500.000 ₫: VND amounts are wide.
const _amount = 125000000;
const _bigAmount = 1250000000;

final _members = [
  testMember('m1', name: _payer),
  testMember('m2', name: _receiver),
];

/// How many lines [finder]'s text is laid out on.
int _lines(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final length = paragraph.text.toPlainText().length;
  return paragraph
      .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: length))
      .map((box) => box.top.round())
      .toSet()
      .length;
}

void main() {
  for (final locale in const [Locale('en'), Locale('vi')]) {
    for (final brightness in Brightness.values) {
      final label = '${locale.languageCode}, ${brightness.name}';

      Future<void> pump(WidgetTester tester, Widget child) async {
        tester.view.physicalSize = const Size(360, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            memberListProvider('g1')
                .overrideWith((ref) => Stream.value(_members)),
          ],
          child: MaterialApp(
            locale: locale,
            theme: brightness == Brightness.light
                ? AppTheme.light()
                : AppTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: ListView(children: [child])),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      testWidgets('expense row wraps a long title ($label)', (tester) async {
        await pump(
          tester,
          ExpenseListTile(
            expense:
                testExpense(amountCents: _bigAmount).copyWith(title: _title),
            members: _members,
          ),
        );
        expect(_lines(tester, find.text(_title)), 2);
      });

      testWidgets('group card wraps a long name ($label)', (tester) async {
        await pump(
          tester,
          GroupCard(group: testGroup().copyWith(name: _groupName)),
        );
        expect(_lines(tester, find.text(_groupName)), 2);
      });

      testWidgets(
          'debt card puts payer and receiver on their own lines '
          '($label)', (tester) async {
        await pump(
          tester,
          DebtCard(
            debt: Debt(
              from: _members[0],
              to: _members[1],
              amountCents: _bigAmount,
              currencyCode: 'VND',
            ),
            currencyCode: 'VND',
            onSettle: () {},
          ),
        );
        // Each name has a line of its own instead of half of a shared row.
        final payer = find.text(_payer);
        final receiver = find.text(_receiver);
        expect(tester.getTopLeft(receiver).dy,
            greaterThanOrEqualTo(tester.getBottomLeft(payer).dy));
        expect(_lines(tester, payer), lessThanOrEqualTo(2));
      });

      testWidgets('settlement row shows both long names ($label)',
          (tester) async {
        await pump(
          tester,
          SettlementListTile(
            settlement: Settlement(
              id: 's1',
              groupId: 'g1',
              fromMemberId: 'm1',
              toMemberId: 'm2',
              amountCents: _amount,
              currencyCode: 'VND',
              settledAt: testDate,
              createdAt: testDate,
            ),
            members: _members,
          ),
        );
        expect(_lines(tester, find.textContaining(_receiver)), 2);
      });
    }
  }
}
