import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simsplit/presentation/router/app_router.dart';

void main() {
  testWidgets('pushed screens are reported by their own route pattern',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Text('home'),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (_, __) => const Text('settings'),
            routes: [
              GoRoute(
                  path: 'diagnostics',
                  builder: (_, __) => const Text('diagnostics')),
            ],
          ),
          GoRoute(
              path: 'groups/:groupId', builder: (_, __) => const Text('group')),
        ],
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    String pattern() =>
        screenPattern(router.routerDelegate.currentConfiguration);

    expect(pattern(), '/');
    router.go('/groups/g1');
    await tester.pumpAndSettle();
    expect(pattern(), '/groups/:groupId');
    unawaited(router.push('/settings'));
    await tester.pumpAndSettle();
    expect(pattern(), '/settings');
    unawaited(router.push('/settings/diagnostics'));
    await tester.pumpAndSettle();
    expect(pattern(), '/settings/diagnostics');
    router.pop();
    await tester.pumpAndSettle();
    expect(pattern(), '/settings');
  });
}
