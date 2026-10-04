import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/data/repositories/firebase_auth_repository.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUser extends Mock implements fb.User {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleAccount extends Mock implements GoogleSignInAccount {}

void main() {
  late _MockFirebaseAuth firebaseAuth;
  late _MockGoogleSignIn google;
  late _MockUser user;
  var online = true;

  FirebaseAuthRepository repository() => FirebaseAuthRepository(
        firebaseAuth: firebaseAuth,
        googleSignIn: google,
        serverClientId: 'server-client',
        canConnect: () async => online,
      );

  setUpAll(() {
    registerFallbackValue(fb.GoogleAuthProvider.credential(idToken: 'x'));
  });

  setUp(() {
    online = true;
    firebaseAuth = _MockFirebaseAuth();
    google = _MockGoogleSignIn();
    user = _MockUser();
    when(() => user.uid).thenReturn('u1');
    when(() => user.email).thenReturn('khoi@example.com');
    when(() => user.displayName).thenReturn('Khoi');

    final account = _MockGoogleAccount();
    when(() => account.authentication)
        .thenReturn(const GoogleSignInAuthentication(idToken: 'id-token'));
    when(() => google.initialize(serverClientId: any(named: 'serverClientId')))
        .thenAnswer((_) async {});
    when(() => google.authenticate()).thenAnswer((_) async => account);
    when(() => google.signOut()).thenAnswer((_) async {});
    when(() => google.disconnect()).thenAnswer((_) async {});
  });

  GoogleSignInException googleError(GoogleSignInExceptionCode code) =>
      GoogleSignInException(code: code);

  group('signInWithGoogle', () {
    test('signs in to Firebase with the Google ID token', () async {
      final credential = _MockUserCredential();
      when(() => credential.user).thenReturn(user);
      when(() => firebaseAuth.signInWithCredential(any()))
          .thenAnswer((_) async => credential);

      final result = await repository().signInWithGoogle();

      expect(
        result.toNullable(),
        const AuthUser(
            uid: 'u1', email: 'khoi@example.com', displayName: 'Khoi'),
      );
      verify(() => google.initialize(serverClientId: 'server-client'))
          .called(1);
      final sent = verify(() => firebaseAuth.signInWithCredential(captureAny()))
          .captured
          .single as fb.OAuthCredential;
      expect(sent.idToken, 'id-token');
    });

    test('reports a closed Google sheet as cancelled', () async {
      when(() => google.authenticate())
          .thenThrow(googleError(GoogleSignInExceptionCode.canceled));

      final result = await repository().signInWithGoogle();

      expect(result.getLeft().toNullable(), isA<AuthCancelled>());
    });

    test('reports a Google error while offline as no connection', () async {
      online = false;
      when(() => google.authenticate())
          .thenThrow(googleError(GoogleSignInExceptionCode.unknownError));

      final result = await repository().signInWithGoogle();

      expect(result.getLeft().toNullable(), isA<AuthNoConnection>());
    });

    test('reports a Google error while online as a failed sign-in', () async {
      when(() => google.authenticate()).thenThrow(
          googleError(GoogleSignInExceptionCode.clientConfigurationError));

      final result = await repository().signInWithGoogle();

      expect(result.getLeft().toNullable(), isA<AuthSignInFailed>());
    });

    test('reports a Firebase network error as no connection', () async {
      when(() => firebaseAuth.signInWithCredential(any()))
          .thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));

      final result = await repository().signInWithGoogle();

      expect(result.getLeft().toNullable(), isA<AuthNoConnection>());
    });

    test('initialises Google sign-in only once', () async {
      when(() => google.authenticate())
          .thenThrow(googleError(GoogleSignInExceptionCode.canceled));
      final repo = repository();

      await repo.signInWithGoogle();
      await repo.signInWithGoogle();

      verify(() => google.initialize(serverClientId: 'server-client'))
          .called(1);
    });
  });

  group('signOut', () {
    test('signs out of Firebase and forgets the Google account', () async {
      when(() => firebaseAuth.signOut()).thenAnswer((_) async {});

      final result = await repository().signOut();

      expect(result.isRight(), isTrue);
      verify(() => firebaseAuth.signOut()).called(1);
      verify(() => google.signOut()).called(1);
    });
  });

  group('deleteAccount', () {
    setUp(() => when(() => firebaseAuth.currentUser).thenReturn(user));

    test('deletes the Firebase user', () async {
      when(() => user.delete()).thenAnswer((_) async {});

      final result = await repository().deleteAccount();

      expect(result.isRight(), isTrue);
      verify(() => user.delete()).called(1);
      verifyNever(() => google.authenticate());
    });

    test('confirms with Google again when the sign-in is not recent', () async {
      var attempts = 0;
      when(() => user.delete()).thenAnswer((_) async {
        if (attempts++ == 0) {
          throw fb.FirebaseAuthException(code: 'requires-recent-login');
        }
      });
      when(() => user.reauthenticateWithCredential(any()))
          .thenAnswer((_) async => _MockUserCredential());

      final result = await repository().deleteAccount();

      expect(result.isRight(), isTrue);
      verify(() => user.reauthenticateWithCredential(any())).called(1);
      verify(() => user.delete()).called(2);
    });

    test('keeps the account when the user cancels the confirmation', () async {
      when(() => user.delete())
          .thenThrow(fb.FirebaseAuthException(code: 'requires-recent-login'));
      when(() => google.authenticate())
          .thenThrow(googleError(GoogleSignInExceptionCode.canceled));

      final result = await repository().deleteAccount();

      expect(result.getLeft().toNullable(), isA<AuthCancelled>());
      verify(() => user.delete()).called(1);
    });
  });
}
