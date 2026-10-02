import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simsplit/presentation/router/app_router.dart';

void main() {
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
}
