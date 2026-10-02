import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';
import 'package:simsplit/domain/use_cases/members/remove_member.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockMemberRepository members;
  late RemoveMember useCase;

  setUp(() {
    members = MockMemberRepository();
    useCase = RemoveMember(memberRepository: members);
    when(() => members.getMember('m1'))
        .thenAnswer((_) async => right(testMember('m1')));
    when(() => members.isMemberReferenced('m1'))
        .thenAnswer((_) async => right(false));
    when(() => members.removeMember('m1')).thenAnswer((_) async => right(unit));
  });

  const params = RemoveMemberParams(memberId: 'm1', groupId: 'g1');

  test('removes a member without history', () async {
    final result = await useCase(params);

    expect(result.isRight(), isTrue);
    verify(() => members.removeMember('m1')).called(1);
  });

  test('blocks removal when member has history', () async {
    when(() => members.isMemberReferenced('m1'))
        .thenAnswer((_) async => right(true));

    final result = await useCase(params);

    expect(leftOf(result), isA<MemberHasHistory>());
    verifyNever(() => members.removeMember(any()));
  });

  test('rejects member from another group', () async {
    when(() => members.getMember('m1'))
        .thenAnswer((_) async => right(testMember('m1', groupId: 'g2')));

    final result = await useCase(params);

    expect(leftOf(result), isA<MemberNotInGroup>());
    verifyNever(() => members.removeMember(any()));
  });

  test('returns notFound for missing member', () async {
    when(() => members.getMember('m1')).thenAnswer(
      (_) async => left<Failure, Member>(const MemberFailure.notFound()),
    );

    final result = await useCase(params);

    expect(leftOf(result), isA<MemberNotFound>());
    verifyNever(() => members.removeMember(any()));
  });

  test('propagates reference-check failure', () async {
    when(() => members.isMemberReferenced('m1')).thenAnswer(
      (_) async => left<Failure, bool>(const Failure.dbFailure('boom')),
    );

    final result = await useCase(params);

    expect(leftOf(result), isA<DbFailure>());
    verifyNever(() => members.removeMember(any()));
  });
}
