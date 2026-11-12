import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/invite_failure.dart';
import 'package:simsplit/domain/use_cases/invites/join_group.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockInviteRepository invites;
  late MockAuthRepository auth;
  late MockUserProfileRepository profiles;
  const user = AuthUser(uid: 'u1');

  setUpAll(() => registerFallbackValue(user));

  setUp(() {
    invites = MockInviteRepository();
    auth = MockAuthRepository();
    profiles = MockUserProfileRepository();
    when(() => auth.watchCurrentUser())
        .thenAnswer((_) => Stream.value(right<Failure, AuthUser?>(user)));
    when(() => invites.joinGroup(any()))
        .thenAnswer((_) async => right<Failure, String>('g1'));
  });

  JoinGroup joinGroup() => JoinGroup(
        inviteRepository: invites,
        authRepository: auth,
        userProfileRepository: profiles,
        policyVersion: '2026-10-24',
      );

  test(
      'a first sign-in from an invite link joins, because the agreement '
      'is stored before the invite is read (#107)', () async {
    // The rules deny reading the invite until the agreement exists.
    var agreed = false;
    when(() => profiles.recordAgreement(any(), any())).thenAnswer((_) async {
      agreed = true;
      return right<Failure, Unit>(unit);
    });
    when(() => invites.joinGroup(any())).thenAnswer((_) async => agreed
        ? right<Failure, String>('g1')
        : left<Failure, String>(const InviteFailure.invalidLink()));

    final result = await joinGroup()('tok');

    expect(result, right<Failure, String>('g1'));
    verifyInOrder([
      () => profiles.recordAgreement(user, '2026-10-24'),
      () => invites.joinGroup('tok'),
    ]);
  });

  test('does not join when the agreement cannot be stored', () async {
    when(() => profiles.recordAgreement(any(), any())).thenAnswer(
        (_) async => left<Failure, Unit>(const Failure.unexpected('offline')));

    final result = await joinGroup()('tok');

    expect(result.isLeft(), isTrue);
    verifyNever(() => invites.joinGroup(any()));
  });

  test('does not join when signed out', () async {
    when(() => auth.watchCurrentUser())
        .thenAnswer((_) => Stream.value(right<Failure, AuthUser?>(null)));

    final result = await joinGroup()('tok');

    expect(result.isLeft(), isTrue);
    verifyNever(() => profiles.recordAgreement(any(), any()));
    verifyNever(() => invites.joinGroup(any()));
  });
}
