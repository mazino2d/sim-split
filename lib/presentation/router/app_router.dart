import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const GroupListScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/groups/form',
      builder: (context, state) => const GroupFormScreen(),
    ),
    GoRoute(
      path: '/groups/:groupId',
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
            return ExpenseDetailScreen(groupId: groupId, expenseId: expenseId);
          },
        ),
        GoRoute(
          path: 'expenses/:expenseId/edit',
          builder: (context, state) {
            final groupId = state.pathParameters['groupId']!;
            final expenseId = state.pathParameters['expenseId']!;
            return ExpenseFormScreen(
                groupId: groupId, editExpenseId: expenseId);
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
            final member = state.extra as Member?;
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
            final extra = state.extra as Map<String, dynamic>?;
            return SettlementFormScreen(
              groupId: groupId,
              fromMemberId: extra?['fromMemberId'] as String?,
              toMemberId: extra?['toMemberId'] as String?,
              suggestedAmountCents: extra?['amountCents'] as int?,
            );
          },
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text('Page not found: ${state.error}')),
  ),
);
