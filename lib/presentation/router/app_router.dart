import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/screens/expenses/expense_detail_screen.dart';
import 'package:simsplit/presentation/screens/expenses/expense_form_screen.dart';
import 'package:simsplit/presentation/screens/groups/group_detail_screen.dart';
import 'package:simsplit/presentation/screens/groups/group_form_screen.dart';
import 'package:simsplit/presentation/screens/groups/group_list_screen.dart';
import 'package:simsplit/presentation/screens/members/member_form_screen.dart';
import 'package:simsplit/presentation/screens/settings/settings_screen.dart';
import 'package:simsplit/presentation/screens/settlements/debt_overview_screen.dart';
import 'package:simsplit/presentation/screens/settlements/settlement_form_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  // All screens are nested under '/' so the group list is always at the
  // bottom of the stack: `context.go('/groups/<id>')` then yields
  // [GroupList, GroupDetail] and Back returns to the list instead of
  // exiting the app.
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const GroupListScreen(),
      routes: [
        GoRoute(
          path: 'settings',
          builder: (context, state) => const SettingsScreen(),
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
                return MemberFormScreen(groupId: groupId, editMember: member);
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
                final args = extra is Map ? extra : const <String, Object>{};
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
