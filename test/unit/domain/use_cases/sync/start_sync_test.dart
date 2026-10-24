import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/sync/start_sync.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockSyncRepository sync;
  late MockUserProfileRepository profiles;
  const user = AuthUser(uid: 'u1');

  setUpAll(() => registerFallbackValue(user));

  setUp(() {
    sync = MockSyncRepository();
    profiles = MockUserProfileRepository();
    when(() => sync.start(any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));
  });

  StartSync startSync() => StartSync(
        syncRepository: sync,
        userProfileRepository: profiles,
        policyVersion: '2026-10-24',
      );

  test('stores the agreement before syncing, since the rules require it',
      () async {
    when(() => profiles.recordAgreement(any(), any()))
        .thenAnswer((_) async => right<Failure, Unit>(unit));

    final result = await startSync()(user);

    expect(result.isRight(), isTrue);
    verifyInOrder([
      () => profiles.recordAgreement(user, '2026-10-24'),
      () => sync.start(user),
    ]);
  });

  test('does not sync when the agreement cannot be stored', () async {
    when(() => profiles.recordAgreement(any(), any())).thenAnswer(
        (_) async => left<Failure, Unit>(const Failure.unexpected('offline')));

    final result = await startSync()(user);

    expect(result.isLeft(), isTrue);
    verifyNever(() => sync.start(any()));
  });
}
