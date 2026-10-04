import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/auth/delete_account.dart';
import 'package:simsplit/domain/use_cases/auth/sign_out.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockAuthRepository auth;
  late MockLocalDataRepository localData;

  setUp(() {
    auth = MockAuthRepository();
    localData = MockLocalDataRepository();
    when(() => localData.clearAll())
        .thenAnswer((_) async => right<Failure, Unit>(unit));
  });

  group('SignOut', () {
    test('clears the data on this device after signing out', () async {
      when(() => auth.signOut())
          .thenAnswer((_) async => right<Failure, Unit>(unit));

      final result = await SignOut(
        authRepository: auth,
        localDataRepository: localData,
      )(const NoParams());

      expect(result.isRight(), isTrue);
      verifyInOrder([() => auth.signOut(), () => localData.clearAll()]);
    });

    test('keeps the data when signing out fails', () async {
      when(() => auth.signOut()).thenAnswer(
          (_) async => left<Failure, Unit>(const AuthFailure.signInFailed()));

      final result = await SignOut(
        authRepository: auth,
        localDataRepository: localData,
      )(const NoParams());

      expect(result.getLeft().toNullable(), isA<AuthSignInFailed>());
      verifyNever(() => localData.clearAll());
    });
  });

  group('DeleteAccount', () {
    test('clears the data on this device after deleting the account', () async {
      when(() => auth.deleteAccount())
          .thenAnswer((_) async => right<Failure, Unit>(unit));

      final result = await DeleteAccount(
        authRepository: auth,
        localDataRepository: localData,
      )(const NoParams());

      expect(result.isRight(), isTrue);
      verifyInOrder([() => auth.deleteAccount(), () => localData.clearAll()]);
    });

    test('keeps the data when the user cancels the confirmation', () async {
      when(() => auth.deleteAccount()).thenAnswer(
          (_) async => left<Failure, Unit>(const AuthFailure.cancelled()));

      final result = await DeleteAccount(
        authRepository: auth,
        localDataRepository: localData,
      )(const NoParams());

      expect(result.getLeft().toNullable(), isA<AuthCancelled>());
      verifyNever(() => localData.clearAll());
    });
  });
}
