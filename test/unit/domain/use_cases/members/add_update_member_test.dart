import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/failures/member_failure.dart';
import 'package:simsplit/domain/use_cases/members/add_member.dart';
import 'package:simsplit/domain/use_cases/members/update_member.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockMemberRepository members;

  setUpAll(registerEntityFallbacks);

  setUp(() {
    members = MockMemberRepository();
    when(() => members.addMember(any()))
        .thenAnswer((inv) async => right(inv.positionalArguments.first));
    when(() => members.updateMember(any()))
        .thenAnswer((inv) async => right(inv.positionalArguments.first));
  });

  group('AddMember', () {
    test('adds a member with trimmed name', () async {
      final result = await AddMember(memberRepository: members)(
        const AddMemberParams(groupId: 'g1', name: '  Alice  '),
      );

      final member = result.getOrElse((f) => throw StateError('$f'));
      expect(member.name, 'Alice');
      verify(() => members.addMember(any())).called(1);
    });

    for (final name in ['', '   ', '\t\n']) {
      test('rejects blank name "${name.replaceAll('\n', r'\n')}"', () async {
        final result = await AddMember(memberRepository: members)(
          AddMemberParams(groupId: 'g1', name: name),
        );

        expect(leftOf(result), isA<MemberNameEmpty>());
        verifyNever(() => members.addMember(any()));
      });
    }
  });

  group('UpdateMember', () {
    UpdateMemberParams params(String name) => UpdateMemberParams(
          id: 'm1',
          groupId: 'g1',
          name: name,
          avatarColorValue: 0,
          isMe: false,
          createdAt: testDate,
        );

    test('updates a member', () async {
      final result =
          await UpdateMember(memberRepository: members)(params('Bob'));

      expect(result.isRight(), isTrue);
      verify(() => members.updateMember(any())).called(1);
    });

    test('rejects blank name', () async {
      final result = await UpdateMember(memberRepository: members)(params(' '));

      expect(leftOf(result), isA<MemberNameEmpty>());
      verifyNever(() => members.updateMember(any()));
    });
  });
}
