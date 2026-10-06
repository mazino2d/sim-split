import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/presentation/router/app_routes.dart';
import 'package:simsplit/presentation/screens/auth/sign_in_screen.dart';
import 'package:simsplit/presentation/screens/expenses/expense_detail_screen.dart';
import 'package:simsplit/presentation/screens/expenses/expense_form_screen.dart';
import 'package:simsplit/presentation/screens/groups/group_detail_screen.dart';
import 'package:simsplit/presentation/screens/groups/group_form_screen.dart';
import 'package:simsplit/presentation/screens/groups/group_list_screen.dart';
import 'package:simsplit/presentation/screens/groups/join_group_screen.dart';
import 'package:simsplit/presentation/screens/members/member_form_screen.dart';
import 'package:simsplit/presentation/screens/settings/settings_screen.dart';
import 'package:simsplit/presentation/screens/settlements/debt_overview_screen.dart';
import 'package:simsplit/presentation/screens/settlements/settlement_form_screen.dart';

part 'app_router.g.dart';

/// Where to send the user given the auth state, or `null` to stay. Sign-in
/// is required wherever accounts are available (R-3 AC1): while the stored
/// session loads, the app waits on a blank screen under the native splash.
/// An invite link opened before sign-in is kept through the gate as `from`,
/// so the friend lands on its join screen right after (AC12).
String? authRedirect(AsyncValue<AuthUser?> auth, Uri uri) {
  final location = uri.path;
  final onGate = location == AppRoutes.signIn || location == AppRoutes.starting;
  final from = onGate
      ? uri.queryParameters['from']
      : (location.startsWith('/join/') ? location : null);
  String gate(String path) => from == null
      ? path
      : Uri(path: path, queryParameters: {'from': from}).toString();

  if (!auth.hasValue && !auth.hasError) {
    return location == AppRoutes.starting ? null : gate(AppRoutes.starting);
  }
  final signedIn = auth.hasValue && auth.value != null;
  if (!signedIn) {
    return location == AppRoutes.signIn ? null : gate(AppRoutes.signIn);
  }
  return onGate ? (from ?? AppRoutes.home) : null;
}

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final authAvailable = ref.watch(authAvailableProvider);
  final authChanged = ValueNotifier(0);
  if (authAvailable) {
    ref.listen(currentUserProvider, (_, __) => authChanged.value++);
  }
  final router = _buildRouter(
    refreshListenable: authChanged,
    redirect: authAvailable
        ? (context, state) =>
            authRedirect(ref.read(currentUserProvider), state.uri)
        : null,
  );
  ref.onDispose(() {
    router.dispose();
    authChanged.dispose();
  });
  return router;
}

GoRouter _buildRouter({
  required Listenable refreshListenable,
  required GoRouterRedirect? redirect,
}) =>
    GoRouter(
      initialLocation: '/',
      refreshListenable: refreshListenable,
      redirect: redirect,
      // All screens are nested under '/' so the group list is always at the
      // bottom of the stack: `context.go('/groups/<id>')` then yields
      // [GroupList, GroupDetail] and Back returns to the list instead of
      // exiting the app.
      routes: [
        // Outside '/' so Back from them exits the app instead of revealing the
        // group list.
        GoRoute(
          path: AppRoutes.starting,
          builder: (context, state) => const Scaffold(),
        ),
        GoRoute(
          path: AppRoutes.signIn,
          builder: (context, state) => const SignInScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) => const GroupListScreen(),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (context, state) => const SettingsScreen(),
            ),
            GoRoute(
              path: 'join/:token',
              builder: (context, state) =>
                  JoinGroupScreen(token: state.pathParameters['token']!),
            ),
            GoRoute(
              path: 'groups/form',
              builder: (context, state) => const GroupFormScreen(),
            ),
            GoRoute(
              path: 'groups/:groupId',
              builder: (context, state) {
                final groupId = state.pathParameters['groupId']!;
                return GroupDetailScreen(groupId: groupId);
              },
              routes: [
                GoRoute(
                  path: 'edit',
                  builder: (context, state) {
                    final groupId = state.pathParameters['groupId']!;
                    return GroupFormScreen(editGroupId: groupId);
                  },
                ),
                GoRoute(
                  path: 'expenses/add',
                  builder: (context, state) {
                    final groupId = state.pathParameters['groupId']!;
                    return ExpenseFormScreen(groupId: groupId);
                  },
                ),
                GoRoute(
                  path: 'expenses/:expenseId',
                  builder: (context, state) {
                    final groupId = state.pathParameters['groupId']!;
                    final expenseId = state.pathParameters['expenseId']!;
                    return ExpenseDetailScreen(
                        groupId: groupId, expenseId: expenseId);
                  },
                ),
                GoRoute(
                  path: 'expenses/:expenseId/edit',
                  builder: (context, state) {
                    final groupId = state.pathParameters['groupId']!;
                    final expenseId = state.pathParameters['expenseId']!;
                    return ExpenseFormScreen(
                      groupId: groupId,
                      editExpenseId: expenseId,
                      focusTitle: state.uri.queryParameters['focus'] == 'title',
                    );
                  },
                ),
                GoRoute(
                  path: 'members/add',
                  builder: (context, state) {
                    final groupId = state.pathParameters['groupId']!;
                    return MemberFormScreen(groupId: groupId);
                  },
                ),
                GoRoute(
                  path: 'members/:memberId/edit',
                  builder: (context, state) {
                    final groupId = state.pathParameters['groupId']!;
                    final extra = state.extra;
                    final member = extra is Member ? extra : null;
                    return MemberFormScreen(
                        groupId: groupId, editMember: member);
                  },
                ),
                GoRoute(
                  path: 'debts',
                  builder: (context, state) {
                    final groupId = state.pathParameters['groupId']!;
                    return DebtOverviewScreen(groupId: groupId);
                  },
                ),
                GoRoute(
                  path: 'settle',
                  builder: (context, state) {
                    final groupId = state.pathParameters['groupId']!;
                    final extra = state.extra;
                    final args =
                        extra is Map ? extra : const <String, Object>{};
                    final from = args['fromMemberId'];
                    final to = args['toMemberId'];
                    final amount = args['amountCents'];
                    return SettlementFormScreen(
                      groupId: groupId,
                      fromMemberId: from is String ? from : null,
                      toMemberId: to is String ? to : null,
                      suggestedAmountCents: amount is int ? amount : null,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ],
      errorBuilder: (context, state) => const _NotFoundScreen(),
    );

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.pageNotFound),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/'),
              child: Text(l10n.goBack),
            ),
          ],
        ),
      ),
    );
  }
}
