import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/presentation/router/app_router.dart';

void main() {
  late ProviderContainer container;
  late GoRouter appRouter;

  setUp(() {
    container = ProviderContainer(
      overrides: [authAvailableProvider.overrideWithValue(false)],
    );
    appRouter = container.read(appRouterProvider);
  });

  tearDown(() => container.dispose());

  List<String> matchedPaths(String location) {
    final matches = appRouter.configuration.findMatch(Uri.parse(location));
    return [
      for (final m in matches.matches)
        if (m.route is GoRoute) (m.route as GoRoute).path,
    ];
  }

  group('appRouter', () {
    test('all existing locations resolve', () {
      const locations = [
        '/',
        '/sign-in',
        '/starting',
        '/settings',
        '/groups/form',
        '/groups/g1',
        '/groups/g1/edit',
        '/groups/g1/expenses/add',
        '/groups/g1/expenses/e1',
        '/groups/g1/expenses/e1/edit',
        '/groups/g1/members/add',
        '/groups/g1/members/m1/edit',
        '/groups/g1/debts',
        '/groups/g1/settle',
      ];
      for (final location in locations) {
        final matches = appRouter.configuration.findMatch(Uri.parse(location));
        expect(matches.isError, isFalse, reason: location);
        expect(matches.matches, isNotEmpty, reason: location);
      }
    });

    test('group detail is nested under the group list', () {
      // go('/groups/g1') must keep GroupList below GroupDetail so Back
      // returns to the list instead of exiting the app.
      expect(matchedPaths('/groups/g1'), ['/', 'groups/:groupId']);
    });

    test('groups/form is not captured by groups/:groupId', () {
      expect(matchedPaths('/groups/form'), ['/', 'groups/form']);
    });

    test('unknown locations produce an error match', () {
      final matches =
          appRouter.configuration.findMatch(Uri.parse('/does/not/exist'));
      expect(matches.isError, isTrue);
    });
  });

  group('authRedirect', () {
    const user = AuthUser(uid: 'u1');

    test('waits on the starting screen while the session loads', () {
      expect(authRedirect(const AsyncLoading(), Uri.parse('/groups/g1')),
          '/starting');
      expect(
          authRedirect(const AsyncLoading(), Uri.parse('/starting')), isNull);
    });

    test('sends a signed-out user to sign-in from anywhere', () {
      expect(authRedirect(const AsyncData(null), Uri.parse('/')), '/sign-in');
      expect(authRedirect(const AsyncData(null), Uri.parse('/starting')),
          '/sign-in');
      expect(
          authRedirect(const AsyncData(null), Uri.parse('/sign-in')), isNull);
    });

    test('treats a broken auth state as signed out', () {
      expect(
        authRedirect(AsyncError(Exception(), StackTrace.empty), Uri.parse('/')),
        '/sign-in',
      );
    });

    test('sends a signed-in user from the gate to the group list', () {
      expect(authRedirect(const AsyncData(user), Uri.parse('/sign-in')), '/');
      expect(authRedirect(const AsyncData(user), Uri.parse('/starting')), '/');
    });

    test('keeps an invite link through sign-in (AC12)', () {
      final starting =
          authRedirect(const AsyncLoading(), Uri.parse('/join/t1'));
      expect(starting, '/starting?from=%2Fjoin%2Ft1');
      final signIn = authRedirect(const AsyncData(null), Uri.parse(starting!));
      expect(signIn, '/sign-in?from=%2Fjoin%2Ft1');
      expect(authRedirect(const AsyncData(null), Uri.parse(signIn!)), isNull);
      expect(
          authRedirect(const AsyncData(user), Uri.parse(signIn)), '/join/t1');
    });

    test('join links open under the group list', () {
      expect(matchedPaths('/join/t1'), ['/', 'join/:token']);
    });

    test('leaves a signed-in user where they are', () {
      expect(
          authRedirect(const AsyncData(user), Uri.parse('/groups/g1')), isNull);
    });
  });
}
