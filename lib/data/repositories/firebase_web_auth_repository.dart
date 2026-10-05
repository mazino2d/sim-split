import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:fpdart/fpdart.dart';
import 'package:simsplit/data/mappers/auth_user_mapper.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';

/// Firebase Auth codes for a popup the user closed, or one replaced by a
/// second click: a choice, not an error.
const _cancelledCodes = {
  'popup-closed-by-user',
  'cancelled-popup-request',
  'user-cancelled',
};

/// Firebase Auth with Google sign-in in a popup (web). google_sign_in cannot
/// start a sign-in from the app's own button on web, so Firebase opens
/// Google's page itself. The session is kept in the browser, so a signed-in
/// user stays signed in offline.
class FirebaseWebAuthRepository implements AuthRepository {
  FirebaseWebAuthRepository({
    required fb.FirebaseAuth firebaseAuth,
    fb.GoogleAuthProvider? googleProvider,
    AuthUserMapper mapper = const AuthUserMapper(),
  })  : _firebaseAuth = firebaseAuth,
        // Always show the account picker, as Android does after sign-out.
        _google = googleProvider ??
            (fb.GoogleAuthProvider()
              ..setCustomParameters({'prompt': 'select_account'})),
        _mapper = mapper;

  final fb.FirebaseAuth _firebaseAuth;
  final fb.GoogleAuthProvider _google;
  final AuthUserMapper _mapper;

  @override
  Stream<Either<Failure, AuthUser?>> watchCurrentUser() => _firebaseAuth
      .authStateChanges()
      .map((user) => right<Failure, AuthUser?>(
            user == null ? null : _mapper.toEntity(user),
          ))
      .transform(
        StreamTransformer<Either<Failure, AuthUser?>,
            Either<Failure, AuthUser?>>.fromHandlers(
          handleError: (error, stackTrace, sink) =>
              sink.add(left(AuthFailure.signInFailed(error.toString()))),
        ),
      );

  @override
  Future<Either<Failure, AuthUser>> signInWithGoogle() async {
    try {
      final result = await _firebaseAuth.signInWithPopup(_google);
      final user = result.user;
      if (user == null) return left(const AuthFailure.signInFailed());
      return right(_mapper.toEntity(user));
    } on fb.FirebaseAuthException catch (e) {
      return left(_mapError(e));
    } catch (e) {
      return left(AuthFailure.signInFailed(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> signOut() async {
    try {
      await _firebaseAuth.signOut();
      return right(unit);
    } catch (e) {
      return left(AuthFailure.signInFailed(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return right(unit);
    try {
      try {
        await user.delete();
      } on fb.FirebaseAuthException catch (e) {
        if (e.code != 'requires-recent-login') rethrow;
        // Firebase only deletes accounts with a recent sign-in: confirm with
        // Google once more, then retry.
        await user.reauthenticateWithPopup(_google);
        await user.delete();
      }
      return right(unit);
    } on fb.FirebaseAuthException catch (e) {
      return left(_mapError(e));
    } catch (e) {
      return left(AuthFailure.signInFailed(e.toString()));
    }
  }

  AuthFailure _mapError(fb.FirebaseAuthException e) {
    if (_cancelledCodes.contains(e.code)) return const AuthFailure.cancelled();
    if (e.code == 'network-request-failed') {
      return const AuthFailure.noConnection();
    }
    return AuthFailure.signInFailed('${e.code}: ${e.message}');
  }
}
