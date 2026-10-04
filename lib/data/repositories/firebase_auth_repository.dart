import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:fpdart/fpdart.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:simsplit/data/mappers/auth_user_mapper.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/auth_repository.dart';

/// Checks whether the sign-in servers can be reached. Used after a failed
/// sign-in, because the Google SDK does not report "offline" on its own.
typedef ConnectionProbe = Future<bool> Function();

Future<bool> _canReachGoogle() async {
  try {
    final result = await InternetAddress.lookup('accounts.google.com')
        .timeout(const Duration(seconds: 3));
    return result.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Firebase Auth with Google sign-in (Android). The Firebase session is
/// persisted on the device, so a signed-in user stays signed in offline.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required fb.FirebaseAuth firebaseAuth,
    required GoogleSignIn googleSignIn,
    required String serverClientId,
    AuthUserMapper mapper = const AuthUserMapper(),
    ConnectionProbe canConnect = _canReachGoogle,
  })  : _firebaseAuth = firebaseAuth,
        _googleSignIn = googleSignIn,
        _serverClientId = serverClientId,
        _mapper = mapper,
        _canConnect = canConnect;

  final fb.FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final String _serverClientId;
  final AuthUserMapper _mapper;
  final ConnectionProbe _canConnect;

  // GoogleSignIn.initialize must run exactly once, before any other call.
  Future<void>? _googleReady;

  Future<void> _initGoogle() => _googleReady ??=
      _googleSignIn.initialize(serverClientId: _serverClientId);

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
      final credential = await _googleCredential();
      final result = await _firebaseAuth.signInWithCredential(credential);
      final user = result.user;
      if (user == null) return left(const AuthFailure.signInFailed());
      return right(_mapper.toEntity(user));
    } on GoogleSignInException catch (e) {
      return left(await _mapGoogleError(e));
    } on fb.FirebaseAuthException catch (e) {
      return left(_mapFirebaseError(e));
    } catch (e) {
      return left(AuthFailure.signInFailed(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> signOut() async {
    try {
      await _firebaseAuth.signOut();
    } catch (e) {
      return left(AuthFailure.signInFailed(e.toString()));
    }
    // Forget the chosen Google account so the next sign-in shows the picker.
    // The Firebase session is already gone, so a failure here is harmless.
    try {
      await _initGoogle();
      await _googleSignIn.signOut();
    } catch (_) {}
    return right(unit);
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
        await user.reauthenticateWithCredential(await _googleCredential());
        await user.delete();
      }
    } on GoogleSignInException catch (e) {
      return left(await _mapGoogleError(e));
    } on fb.FirebaseAuthException catch (e) {
      return left(_mapFirebaseError(e));
    } catch (e) {
      return left(AuthFailure.signInFailed(e.toString()));
    }
    try {
      await _initGoogle();
      await _googleSignIn.disconnect();
    } catch (_) {}
    return right(unit);
  }

  Future<fb.AuthCredential> _googleCredential() async {
    await _initGoogle();
    final account = await _googleSignIn.authenticate();
    return fb.GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );
  }

  Future<AuthFailure> _mapGoogleError(GoogleSignInException e) async {
    if (e.code == GoogleSignInExceptionCode.canceled) {
      return const AuthFailure.cancelled();
    }
    if (!await _canConnect()) return const AuthFailure.noConnection();
    return AuthFailure.signInFailed('${e.code.name}: ${e.description}');
  }

  AuthFailure _mapFirebaseError(fb.FirebaseAuthException e) =>
      e.code == 'network-request-failed'
          ? const AuthFailure.noConnection()
          : AuthFailure.signInFailed('${e.code}: ${e.message}');
}
