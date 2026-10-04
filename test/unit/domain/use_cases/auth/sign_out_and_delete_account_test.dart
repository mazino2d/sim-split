import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/sync_failure.dart';
import 'package:simsplit/domain/use_cases/auth/delete_account.dart';
import 'package:simsplit/domain/use_cases/auth/sign_out.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockAuthRepository auth;
  late MockLocalDataRepository localData;
  late MockSyncRepository sync;

  setUp(() {
    auth = MockAuthRepository();
    localData = MockLocalDataRepository();
    sync = MockSyncRepository();
    when(() => localData.clearAll())
        .thenAnswer((_) async => right<Failure, Unit>(unit));
    when(() => sync.pendingChangeCount())
        .thenAnswer((_) async => right<Failure, int>(0));
    when(() => sync.stop()).thenAnswer((_) async => right<Failure, Unit>(unit));
    when(() => sync.deleteCloudData())
        .thenAnswer((_) async => right<Failure, Unit>(unit));
  });

  SignOut signOut() => SignOut(
        authRepository: auth,
        localDataRepository: localData,
        syncRepository: sync,
      );

  DeleteAccount deleteAccount() => DeleteAccount(
        authRepository: auth,
        localDataRepository: localData,
        syncRepository: sync,
      );

  group('SignOut', () {
    test('clears the data on this device after signing out', () async {
      when(() => auth.signOut())
          .thenAnswer((_) async => right<Failure, Unit>(unit));

      final result = await signOut()(const NoParams());

      expect(result.isRight(), isTrue);
      verifyInOrder([
        () => auth.signOut(),
        () => sync.stop(),
        () => localData.clearAll(),
      ]);
    });

    test('keeps the data when signing out fails', () async {
      when(() => auth.signOut()).thenAnswer(
          (_) async => left<Failure, Unit>(const AuthFailure.signInFailed()));

      final result = await signOut()(const NoParams());

      expect(result.getLeft().toNullable(), isA<AuthSignInFailed>());
      verifyNever(() => localData.clearAll());
    });

    test('refuses while changes are waiting to be pushed', () async {
      when(() => sync.pendingChangeCount())
          .thenAnswer((_) async => right<Failure, int>(3));

      final result = await signOut()(const NoParams());

      expect(
        result.getLeft().toNullable(),
        isA<SyncUnsyncedChanges>().having((f) => f.count, 'count', 3),
      );
      verifyNever(() => auth.signOut());
      verifyNever(() => localData.clearAll());
    });
  });

  group('DeleteAccount', () {
    test('deletes cloud data, then the account, then the device data (AC6)',
        () async {
      when(() => auth.deleteAccount())
          .thenAnswer((_) async => right<Failure, Unit>(unit));

      final result = await deleteAccount()(const NoParams());

      expect(result.isRight(), isTrue);
      verifyInOrder([
        () => sync.deleteCloudData(),
        () => auth.deleteAccount(),
        () => localData.clearAll(),
      ]);
    });

    test('keeps the account and the data when the cloud cannot be reached',
        () async {
      when(() => sync.deleteCloudData()).thenAnswer(
          (_) async => left<Failure, Unit>(const SyncFailure.noConnection()));

      final result = await deleteAccount()(const NoParams());

      expect(result.getLeft().toNullable(), isA<SyncNoConnection>());
      verifyNever(() => auth.deleteAccount());
      verifyNever(() => localData.clearAll());
    });

    test('keeps the data when the user cancels the confirmation', () async {
      when(() => auth.deleteAccount()).thenAnswer(
          (_) async => left<Failure, Unit>(const AuthFailure.cancelled()));

      final result = await deleteAccount()(const NoParams());

      expect(result.getLeft().toNullable(), isA<AuthCancelled>());
      verifyNever(() => localData.clearAll());
    });
  });
}
