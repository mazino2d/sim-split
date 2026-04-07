import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/group.dart';
import '../../../domain/entities/member.dart';
import '../../notifiers/expense_notifier.dart';
import '../../notifiers/group_notifier.dart';
import '../../notifiers/member_notifier.dart';
import '../../providers/expense_providers.dart';
import '../../providers/group_providers.dart';
import '../../widgets/common/error_widget.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/expenses/expense_list_tile.dart';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá nhóm?'),
        content: Text('Nhóm "${group.name}" và toàn bộ dữ liệu sẽ bị xoá vĩnh viễn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá'),
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
              tooltip: 'Xem số dư',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Xoá nhóm',
              onPressed: () => _confirmDeleteGroup(context, ref),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Chi tiêu'),
              Tab(text: 'Thành viên'),
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
    final expensesAsync = ref.watch(expenseListProvider(group.id));
    final membersAsync = ref.watch(memberListProvider(group.id));
    final members = membersAsync.valueOrNull ?? [];

    return expensesAsync.when(
      data: (expenses) {
        if (expenses.isEmpty) {
          return const Center(child: Text('Chưa có chi tiêu nào'));
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
                    title: const Text('Xoá chi tiêu?'),
                    content: Text('"${expense.title}" sẽ bị xoá.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, false),
                        child: const Text('Huỷ'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(dCtx, true),
                        child: const Text('Xoá'),
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
                    SnackBar(content: Text('Đã xoá "${expense.title}"')),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá thành viên?'),
        content: Text('"${member.name}" sẽ bị xoá khỏi nhóm.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá'),
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
                'Không thể xoá: thành viên còn chi tiêu chưa thanh toán.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(memberListProvider(group.id));

    return membersAsync.when(
      data: (members) {
        if (members.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Chưa có thành viên nào'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      context.push('/groups/${group.id}/members/add'),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Thêm thành viên'),
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
                title: const Text('Thêm thành viên'),
                onTap: () =>
                    context.push('/groups/${group.id}/members/add'),
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
              subtitle: member.isMe ? const Text('Tôi') : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Sửa',
                    onPressed: () => context.push(
                      '/groups/${group.id}/members/${member.id}/edit',
                      extra: member,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Xoá',
                    onPressed: () =>
                        _confirmRemoveMember(context, ref, member),
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
