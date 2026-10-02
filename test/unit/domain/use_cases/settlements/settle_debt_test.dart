import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';
import 'package:simsplit/domain/failures/settlement_failure.dart';
import 'package:simsplit/domain/use_cases/settlements/settle_debt.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockSettlementRepository settlements;
  late MockMemberRepository members;
  late SettleDebt useCase;

  setUpAll(registerEntityFallbacks);

  setUp(() {
    settlements = MockSettlementRepository();
    members = MockMemberRepository();
    useCase = SettleDebt(
      settlementRepository: settlements,
      memberRepository: members,
    );
    when(() => members.getMember('m1'))
        .thenAnswer((_) async => right(testMember('m1')));
    when(() => members.getMember('m2'))
        .thenAnswer((_) async => right(testMember('m2')));
    when(() => members.getMember('other'))
        .thenAnswer((_) async => right(testMember('other', groupId: 'g2')));
    when(() => members.getMember('ghost')).thenAnswer(
      (_) async => left<Failure, Member>(const MemberFailure.notFound()),
    );
    when(() => settlements.addSettlement(any()))
        .thenAnswer((inv) async => right(inv.positionalArguments.first));
  });

  SettleDebtParams params({
    String from = 'm2',
    String to = 'm1',
    int amountCents = 5000,
  }) =>
      SettleDebtParams(
        groupId: 'g1',
        fromMemberId: from,
        toMemberId: to,
        amountCents: amountCents,
        currencyCode: 'VND',
      );

  test('records a valid settlement', () async {
    final result = await useCase(params());

    final settlement = result.getOrElse((f) => throw StateError('$f'));
    expect(settlement.amountCents, 5000);
    verify(() => settlements.addSettlement(any())).called(1);
  });

  test('rejects zero amount', () async {
    final result = await useCase(params(amountCents: 0));

    expect(leftOf(result), isA<SettlementAmountMustBePositive>());
    verifyNever(() => settlements.addSettlement(any()));
  });

  test('rejects negative amount', () async {
    final result = await useCase(params(amountCents: -1));

    expect(leftOf(result), isA<SettlementAmountMustBePositive>());
  });

  test('rejects paying oneself', () async {
    final result = await useCase(params(from: 'm1', to: 'm1'));

    expect(leftOf(result), isA<SettlementSameMember>());
    verifyNever(() => settlements.addSettlement(any()));
  });

  test('rejects member from another group', () async {
    final result = await useCase(params(to: 'other'));

    expect(leftOf(result), isA<SettlementMemberNotInGroup>());
    verifyNever(() => settlements.addSettlement(any()));
  });

  test('rejects non-existent member', () async {
    final result = await useCase(params(from: 'ghost'));

    expect(leftOf(result), isA<SettlementMemberNotInGroup>());
    verifyNever(() => settlements.addSettlement(any()));
  });
}
