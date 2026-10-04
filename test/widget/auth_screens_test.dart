import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/auth/sign_in_with_google.dart';
import 'package:simsplit/domain/use_cases/auth/sign_out.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/presentation/screens/auth/sign_in_screen.dart';
import 'package:simsplit/presentation/screens/settings/settings_screen.dart';

class _MockSignInWithGoogle extends Mock implements SignInWithGoogle {}

class _MockSignOut extends Mock implements SignOut {}

Widget _app(Widget home, List overrides) => ProviderScope(
      overrides: [...overrides],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

void main() {
  setUpAll(() => registerFallbackValue(const NoParams()));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SignInScreen', () {
    late _MockSignInWithGoogle signIn;

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(_app(const SignInScreen(), [
        signInWithGoogleProvider.overrideWithValue(signIn),
      ]));
      await tester.pumpAndSettle();
    }

    setUp(() => signIn = _MockSignInWithGoogle());

    testWidgets('offers Google sign-in and nothing else to fill in',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('says a connection is needed when offline (AC3)',
        (tester) async {
      when(() => signIn(any())).thenAnswer((_) async =>
          left<Failure, AuthUser>(const AuthFailure.noConnection()));
      await pumpScreen(tester);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(find.text('You need a connection to sign in.'), findsOneWidget);
      // The screen stays usable for a retry.
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('stays quiet when the user closes Google sign-in',
        (tester) async {
      when(() => signIn(any())).thenAnswer(
          (_) async => left<Failure, AuthUser>(const AuthFailure.cancelled()));
      await pumpScreen(tester);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(find.text('You need a connection to sign in.'), findsNothing);
      expect(find.text("Couldn't sign in. Please try again."), findsNothing);
    });
  });

  group('SettingsScreen account section', () {
    const user =
        AuthUser(uid: 'u1', email: 'khoi@example.com', displayName: 'Khoi');

    testWidgets('is hidden where accounts are not available', (tester) async {
      await tester.pumpWidget(_app(const SettingsScreen(), [
        authAvailableProvider.overrideWithValue(false),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Account'), findsNothing);
      expect(find.text('Sign out'), findsNothing);
    });

    testWidgets('signs out only after confirming (AC5)', (tester) async {
      final signOut = _MockSignOut();
      when(() => signOut(any()))
          .thenAnswer((_) async => right<Failure, Unit>(unit));
      await tester.pumpWidget(_app(const SettingsScreen(), [
        authAvailableProvider.overrideWithValue(true),
        currentUserProvider.overrideWith((ref) => Stream.value(user)),
        signOutProvider.overrideWithValue(signOut),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Khoi'), findsOneWidget);
      expect(find.text('khoi@example.com'), findsOneWidget);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      verifyNever(() => signOut(any()));

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();
      verify(() => signOut(any())).called(1);
    });
  });
}
