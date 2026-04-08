import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/notifiers/expense_notifier.dart';
import 'package:simsplit/presentation/notifiers/group_notifier.dart';
import 'package:simsplit/presentation/notifiers/member_notifier.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/widgets/common/error_widget.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';
import 'package:simsplit/presentation/widgets/expenses/expense_list_tile.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupDetailProvider(groupId));

    return groupAsync.when(
      data: (group) => _GroupDetailBody(group: group),
      loading: () => const Scaffold(body: AppLoadingWidget()),
      error: (e, _) => Scaffold(
        body: AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(groupDetailProvider(groupId)),
        ),
      ),
    );
  }
}

class _GroupDetailBody extends ConsumerWidget {
  const _GroupDetailBody({required this.group});

  final Group group;

  Future<void> _confirmDeleteGroup(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteGroupConfirmTitle),
        content: Text(l10n.deleteGroupConfirmMessage(group.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final success =
        await ref.read(groupNotifierProvider.notifier).deleteGroup(group.id);
    if (success && context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${group.emoji ?? ''} ${group.name}'.trim()),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/groups/${group.id}/edit'),
            ),
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              onPressed: () => context.push('/groups/${group.id}/debts'),
              tooltip: l10n.balances,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.deleteGroup,
              onPressed: () => _confirmDeleteGroup(context, ref),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.expenses),
              Tab(text: l10n.members),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ExpensesTab(group: group),
            _MembersTab(group: group),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.push('/groups/${group.id}/expenses/add'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final expensesAsync = ref.watch(expenseListProvider(group.id));
    final membersAsync = ref.watch(memberListProvider(group.id));
    final members = membersAsync.valueOrNull ?? [];

    return expensesAsync.when(
      data: (expenses) {
        if (expenses.isEmpty) {
          return Center(child: Text(l10n.noExpenses));
        }
        return ListView.builder(
          itemCount: expenses.length,
          itemBuilder: (ctx, i) {
            final expense = expenses[i];
            return Dismissible(
              key: ValueKey(expense.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: Colors.red,
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (_) async {
                return await showDialog<bool>(
                  context: ctx,
                  builder: (dCtx) => AlertDialog(
                    title: Text(l10n.deleteExpenseConfirmTitle),
                    content:
                        Text(l10n.deleteExpenseConfirmMessage(expense.title)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, false),
                        child: Text(l10n.cancel),
                      ),
                      FilledButton(
                        style:
                            FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(dCtx, true),
                        child: Text(l10n.delete),
                      ),
                    ],
                  ),
                );
              },
              onDismissed: (_) async {
                await ref
                    .read(expenseNotifierProvider.notifier)
                    .deleteExpense(expense.id);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content:
                            Text(l10n.expenseDeletedMessage(expense.title))),
                  );
                }
              },
              child: ExpenseListTile(
                expense: expense,
                members: members,
                onTap: () => context.push(
                  '/groups/${group.id}/expenses/${expense.id}/edit',
                ),
              ),
            );
          },
        );
      },
      loading: () => const AppLoadingWidget(),
      error: (e, _) => AppErrorWidget(message: e.toString()),
    );
  }
}

class _MembersTab extends ConsumerWidget {
  const _MembersTab({required this.group});

  final Group group;

  Future<void> _confirmRemoveMember(
    BuildContext context,
    WidgetRef ref,
    Member member,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteMemberConfirmTitle),
        content: Text(l10n.deleteMemberConfirmMessage(member.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final success = await ref
        .read(memberNotifierProvider.notifier)
        .removeMember(member.id, group.id);

    if (!success && context.mounted) {
      final error = ref.read(memberNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error?.toString() ??
                AppLocalizations.of(context)!.cannotRemoveMemberWithDebts,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final membersAsync = ref.watch(memberListProvider(group.id));

    return membersAsync.when(
      data: (members) {
        if (members.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(l10n.noMembers),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      context.push('/groups/${group.id}/members/add'),
                  icon: const Icon(Icons.person_add),
                  label: Text(l10n.addMember),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: members.length + 1,
          itemBuilder: (ctx, i) {
            if (i == members.length) {
              return ListTile(
                leading: const Icon(Icons.person_add_outlined),
                title: Text(l10n.addMember),
                onTap: () => context.push('/groups/${group.id}/members/add'),
              );
            }
            final member = members[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Color(member.avatarColorValue),
                child: Text(
                  member.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(member.name),
              subtitle: member.isMe ? Text(l10n.markAsMe) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: l10n.edit,
                    onPressed: () => context.push(
                      '/groups/${group.id}/members/${member.id}/edit',
                      extra: member,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: l10n.removeMember,
                    onPressed: () => _confirmRemoveMember(context, ref, member),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const AppLoadingWidget(),
      error: (e, _) => AppErrorWidget(message: e.toString()),
    );
  }
}
