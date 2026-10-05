import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/data/repositories/firebase_web_auth_repository.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUser extends Mock implements fb.User {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

void main() {
  late _MockFirebaseAuth firebaseAuth;
  late _MockUser user;
  final google = fb.GoogleAuthProvider();

  FirebaseWebAuthRepository repository() => FirebaseWebAuthRepository(
        firebaseAuth: firebaseAuth,
        googleProvider: google,
      );

  setUpAll(() {
    registerFallbackValue(fb.GoogleAuthProvider());
  });

  setUp(() {
    firebaseAuth = _MockFirebaseAuth();
    user = _MockUser();
    when(() => user.uid).thenReturn('u1');
    when(() => user.email).thenReturn('khoi@example.com');
    when(() => user.displayName).thenReturn('Khoi');
  });

  group('signInWithGoogle', () {
    test('signs in to Firebase with a Google popup', () async {
      final credential = _MockUserCredential();
      when(() => credential.user).thenReturn(user);
      when(() => firebaseAuth.signInWithPopup(google))
          .thenAnswer((_) async => credential);

      final result = await repository().signInWithGoogle();

      expect(
        result.toNullable(),
        const AuthUser(
            uid: 'u1', email: 'khoi@example.com', displayName: 'Khoi'),
      );
    });

    for (final code in [
      'popup-closed-by-user',
      'cancelled-popup-request',
      'user-cancelled',
    ]) {
      test('reports $code as cancelled', () async {
        when(() => firebaseAuth.signInWithPopup(any()))
            .thenThrow(fb.FirebaseAuthException(code: code));

        final result = await repository().signInWithGoogle();

        expect(result.getLeft().toNullable(), isA<AuthCancelled>());
      });
    }

    test('reports a network error as no connection', () async {
      when(() => firebaseAuth.signInWithPopup(any()))
          .thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));

      final result = await repository().signInWithGoogle();

      expect(result.getLeft().toNullable(), isA<AuthNoConnection>());
    });

    test('reports a blocked popup as a failed sign-in', () async {
      when(() => firebaseAuth.signInWithPopup(any()))
          .thenThrow(fb.FirebaseAuthException(code: 'popup-blocked'));

      final result = await repository().signInWithGoogle();

      expect(result.getLeft().toNullable(), isA<AuthSignInFailed>());
    });
  });

  group('signOut', () {
    test('signs out of Firebase', () async {
      when(() => firebaseAuth.signOut()).thenAnswer((_) async {});

      final result = await repository().signOut();

      expect(result.isRight(), isTrue);
      verify(() => firebaseAuth.signOut()).called(1);
    });
  });

  group('deleteAccount', () {
    setUp(() => when(() => firebaseAuth.currentUser).thenReturn(user));

    test('deletes the Firebase user', () async {
      when(() => user.delete()).thenAnswer((_) async {});

      final result = await repository().deleteAccount();

      expect(result.isRight(), isTrue);
      verify(() => user.delete()).called(1);
      verifyNever(() => user.reauthenticateWithPopup(any()));
    });

    test('confirms with Google again when the sign-in is not recent', () async {
      var attempts = 0;
      when(() => user.delete()).thenAnswer((_) async {
        if (attempts++ == 0) {
          throw fb.FirebaseAuthException(code: 'requires-recent-login');
        }
      });
      when(() => user.reauthenticateWithPopup(google))
          .thenAnswer((_) async => _MockUserCredential());

      final result = await repository().deleteAccount();

      expect(result.isRight(), isTrue);
      verify(() => user.reauthenticateWithPopup(google)).called(1);
      verify(() => user.delete()).called(2);
    });

    test('keeps the account when the user closes the popup', () async {
      when(() => user.delete())
          .thenThrow(fb.FirebaseAuthException(code: 'requires-recent-login'));
      when(() => user.reauthenticateWithPopup(any()))
          .thenThrow(fb.FirebaseAuthException(code: 'popup-closed-by-user'));

      final result = await repository().deleteAccount();

      expect(result.getLeft().toNullable(), isA<AuthCancelled>());
      verify(() => user.delete()).called(1);
    });
  });
}
