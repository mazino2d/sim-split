import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/auth/sign_in_with_google.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockAuthRepository auth;
  late MockUserProfileRepository profiles;
  const user = AuthUser(uid: 'u1', email: 'a@b.co', displayName: 'An');

  setUpAll(() => registerFallbackValue(user));

  setUp(() {
    auth = MockAuthRepository();
    profiles = MockUserProfileRepository();
    when(() => auth.signOut())
        .thenAnswer((_) async => right<Failure, Unit>(unit));
  });

  SignInWithGoogle signIn() => SignInWithGoogle(
        authRepository: auth,
        userProfileRepository: profiles,
        policyVersion: '2026-10-24',
      );

  test('signing in records the agreement with the policy version (AC7)',
      () async {
    when(() => auth.signInWithGoogle())
        .thenAnswer((_) async => right<Failure, AuthUser>(user));
    when(() => profiles.recordAgreement(any(), any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));

    final result = await signIn()(const NoParams());

    expect(result.toNullable(), user);
    verify(() => profiles.recordAgreement(user, '2026-10-24')).called(1);
    verifyNever(() => auth.signOut());
  });

  test('a sign-in whose agreement cannot be stored is undone', () async {
    when(() => auth.signInWithGoogle())
        .thenAnswer((_) async => right<Failure, AuthUser>(user));
    when(() => profiles.recordAgreement(any(), any())).thenAnswer(
        (_) async => left<Failure, Unit>(const Failure.unexpected('offline')));

    final result = await signIn()(const NoParams());

    expect(result.isLeft(), isTrue);
    verify(() => auth.signOut()).called(1);
  });

  test('a failed sign-in records nothing', () async {
    when(() => auth.signInWithGoogle()).thenAnswer(
        (_) async => left<Failure, AuthUser>(const AuthFailure.cancelled()));

    final result = await signIn()(const NoParams());

    expect(result.getLeft().toNullable(), isA<AuthCancelled>());
    verifyNever(() => profiles.recordAgreement(any(), any()));
  });
}
