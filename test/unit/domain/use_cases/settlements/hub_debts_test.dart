import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/use_cases/settlements/calculate_debts.dart';

// Settling through one collector (#116).

Member _m(String id, {String? uid, bool isMe = false}) => Member(
      id: id,
      groupId: 'g1',
      name: id,
      avatarColorValue: 0,
      createdAt: DateTime(2024),
      linkedUid: uid,
      isMe: isMe,
    );

List<MemberBalance> _balances(Map<Member, int> nets) => [
      for (final e in nets.entries)
        MemberBalance(member: e.key, netAmountCents: e.value),
    ];

/// Each member's net after the suggested transfers.
Map<String, int> _after(List<MemberBalance> balances, List<Debt> debts) {
  final net = {for (final b in balances) b.member.id: b.netAmountCents};
  for (final d in debts) {
    net[d.from.id] = net[d.from.id]! + d.amountCents;
    net[d.to.id] = net[d.to.id]! - d.amountCents;
  }
  return net;
}

void main() {
  final an = _m('an', uid: 'alice');
  final binh = _m('binh');
  final chi = _m('chi');
  final dung = _m('dung');

  List<Debt> hub(List<MemberBalance> balances, Member collector) =>
      hubDebts(balances: balances, collector: collector, currencyCode: 'VND');

  test('debtors pay the collector and creditors are paid by them', () {
    final balances =
        _balances({an: 30000, binh: -50000, chi: 40000, dung: -20000});
    final debts = hub(balances, an);

    expect(debts.map((d) => (d.from.id, d.to.id, d.amountCents)), [
      ('binh', 'an', 50000),
      ('an', 'chi', 40000),
      ('dung', 'an', 20000),
    ]);
    expect(_after(balances, debts).values, everyElement(0));
  });

  test('settles everyone whether the collector is owed, owes or is even', () {
    for (final collectorNet in [30000, -30000, 0]) {
      final balances = _balances({
        an: collectorNet,
        binh: -collectorNet - 10000,
        chi: 10000,
      });
      final debts = hub(balances, an);
      expect(_after(balances, debts).values, everyElement(0),
          reason: 'collector net $collectorNet');
      expect(debts.every((d) => d.from.id == 'an' || d.to.id == 'an'), isTrue);
    }
  });

  test('a member at 0 gets no transfer', () {
    final balances = _balances({an: 10000, binh: -10000, chi: 0});
    expect(hub(balances, an).map((d) => d.from.id), ['binh']);
  });

  group('resolveCollector', () {
    final members = [an, binh.copyWith(isMe: true), chi];

    test('the chosen member while they are in the group', () {
      expect(
          resolveCollector(
              members: members, hubMemberId: 'chi', ownerUid: 'alice'),
          chi);
    });

    test("otherwise the owner's member", () {
      expect(
          resolveCollector(
              members: members, hubMemberId: null, ownerUid: 'alice'),
          an);
      // The chosen collector was removed from the group.
      expect(
          resolveCollector(
              members: members, hubMemberId: 'dung', ownerUid: 'alice'),
          an);
    });

    test("before the group syncs, this device's member", () {
      expect(
          resolveCollector(members: members, hubMemberId: null, ownerUid: null)
              ?.id,
          'binh');
    });

    test('nobody when the owner has no member in the group', () {
      expect(
          resolveCollector(
              members: members, hubMemberId: null, ownerUid: 'zoe'),
          isNull);
    });
  });
}
