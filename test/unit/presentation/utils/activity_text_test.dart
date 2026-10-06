import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simsplit/core/l10n/generated/app_localizations_en.dart';
import 'package:simsplit/domain/entities/activity_entry.dart';
import 'package:simsplit/presentation/utils/activity_text.dart';

import '../../../helpers/mocks.dart';

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  final members = [
    testMember('khoi', name: 'Khoi').copyWith(linkedUid: 'alice', isMe: true),
    testMember('linh', name: 'Linh').copyWith(linkedUid: 'bob'),
  ];

  Map<String, Object?> expense(
          {int amount = 30000000, int linhShare = 15000000}) =>
      {
        'id': 'e1',
        'title': 'Hotpot',
        'amountCents': amount,
        'currencyCode': 'VND',
        'paidByMemberId': 'khoi',
        'splitType': 'exact',
        'category': 'food',
        'note': null,
        'expenseDate': DateTime(2026, 10, 1).millisecondsSinceEpoch,
        'editedAt': 1,
        'updatedBy': 'alice',
        'deleted': false,
        'splits': [
          {
            'id': 's1',
            'memberId': 'khoi',
            'value': amount - linhShare,
            'amountCents': amount - linhShare
          },
          {
            'id': 's2',
            'memberId': 'linh',
            'value': linhShare,
            'amountCents': linhShare
          },
        ],
      };

  ActivityEntry entry(
    ActivityAction action,
    ActivityEntityType type, {
    String actor = 'bob',
    String entityId = 'e1',
    Map<String, Object?>? before,
    Map<String, Object?> after = const {},
  }) =>
      ActivityEntry(
        id: 'a1',
        groupId: 'g1',
        actorUid: actor,
        action: action,
        entityType: type,
        entityId: entityId,
        before: before,
        after: after,
        clientTime: DateTime(2026, 10, 6),
      );

  ActivityText text([List<ActivityEntry> entries = const []]) => ActivityText(
        entries: entries,
        members: members,
        l10n: AppLocalizationsEn(),
        locale: 'en',
        currencyCode: 'VND',
      );

  group('summary (AC25, AC30)', () {
    test('names the member and the item', () {
      final t = text();
      expect(
          t.summary(entry(ActivityAction.create, ActivityEntityType.expense,
              after: expense())),
          'Linh added “Hotpot”');
      expect(
          t.summary(entry(ActivityAction.update, ActivityEntityType.expense,
              actor: 'alice',
              before: expense(),
              after: expense(amount: 36000000))),
          'Khoi (me) edited “Hotpot”');
      expect(
          t.summary(entry(ActivityAction.delete, ActivityEntityType.settlement,
              before: {
                'fromMemberId': 'linh',
                'toMemberId': 'khoi'
              },
              after: {
                'fromMemberId': 'linh',
                'toMemberId': 'khoi',
                'deleted': true
              })),
          'Linh deleted the payment Linh → Khoi');
    });

    test('tells joining, claiming a name and leaving apart', () {
      final t = text();
      expect(t.summary(entry(ActivityAction.join, ActivityEntityType.group)),
          'Linh joined the group');
      expect(
          t.summary(entry(ActivityAction.update, ActivityEntityType.member,
              entityId: 'linh',
              before: {'name': 'Linh', 'linkedUid': null},
              after: {'name': 'Linh', 'linkedUid': 'bob'})),
          'Linh picked the name Linh');
      expect(
          t.summary(entry(ActivityAction.update, ActivityEntityType.member,
              entityId: 'linh',
              before: {'name': 'Linh', 'linkedUid': 'bob'},
              after: {'name': 'Linh', 'linkedUid': null})),
          'Linh left the group');
    });

    test('calls an account that is no longer in the group someone', () {
      expect(
          text().summary(entry(
              ActivityAction.create, ActivityEntityType.expense,
              actor: 'carol', after: expense())),
          'Someone added “Hotpot”');
    });

    test('names removed members from the history', () {
      final removed = entry(ActivityAction.create, ActivityEntityType.member,
          entityId: 'minh', after: {'name': 'Minh'});
      final paid = entry(ActivityAction.create, ActivityEntityType.settlement,
          after: {'fromMemberId': 'minh', 'toMemberId': 'khoi'});
      expect(text([paid, removed]).summary(paid),
          'Linh added the payment Minh → Khoi');
    });
  });

  group('fields', () {
    test('an edit shows only what changed, old → new, shares included (AC26)',
        () {
      final fields = text().fields(entry(
          ActivityAction.update, ActivityEntityType.expense,
          before: expense(),
          after: expense(amount: 36000000, linhShare: 30000000)));

      expect(fields, [
        (label: 'Amount', before: '300.000 ₫', after: '360.000 ₫'),
        (label: "Khoi's share", before: '150.000 ₫', after: '60.000 ₫'),
        (label: "Linh's share", before: '150.000 ₫', after: '300.000 ₫'),
      ]);
    });

    test('a deletion shows the whole record as it was (AC27)', () {
      final fields = text().fields(entry(
          ActivityAction.delete, ActivityEntityType.expense,
          before: expense(), after: {...expense(), 'deleted': true}));

      expect(
          fields.map((f) => f.label),
          containsAllInOrder([
            'Description',
            'Amount',
            'Paid by',
            'Date',
            'Category',
            'Split type'
          ]));
      expect(fields.firstWhere((f) => f.label == 'Paid by').after, 'Khoi');
      expect(fields.every((f) => f.before == null), isTrue);
    });

    test('a join has nothing to show', () {
      expect(
          text().fields(entry(ActivityAction.join, ActivityEntityType.group)),
          isEmpty);
    });
  });
}
