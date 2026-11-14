import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';
import 'package:simsplit/domain/use_cases/profile/my_name.dart';

import '../../../../helpers/mocks.dart';

// "My name", set once and prefilled when creating or joining a group (#112).

void main() {
  group('prefillMyName', () {
    test('the account name first, then this device, then Google', () {
      expect(
          prefillMyName(
              accountName: 'An', lastUsedOnDevice: 'Khoi', displayName: 'Do'),
          'An');
      expect(
          prefillMyName(
              accountName: null, lastUsedOnDevice: 'Khoi', displayName: 'Do'),
          'Khoi');
      expect(
          prefillMyName(
              accountName: '  ', lastUsedOnDevice: null, displayName: 'Do'),
          'Do');
      expect(prefillMyName(), isNull);
    });
  });

  group('SetMyName', () {
    late MockUserProfileRepository profiles;
    late SetMyName useCase;

    setUp(() {
      profiles = MockUserProfileRepository();
      useCase = SetMyName(userProfileRepository: profiles);
      when(() => profiles.setMemberName(any()))
          .thenAnswer((_) async => right<Failure, Unit>(unit));
    });

    test('saves the trimmed name', () async {
      expect((await useCase('  An ')).isRight(), isTrue);
      verify(() => profiles.setMemberName('An')).called(1);
    });

    test('refuses an empty or too long name', () async {
      expect(leftOf(await useCase('  ')), isA<MemberNameEmpty>());
      expect(leftOf(await useCase('x' * (maxMemberNameLength + 1))),
          isA<MemberNameTooLong>());
      verifyNever(() => profiles.setMemberName(any()));
    });
  });
}
