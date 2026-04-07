import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/expense.dart';
import '../../../domain/entities/group.dart';
import '../../providers/expense_providers.dart';
import '../../providers/group_providers.dart';
import '../../providers/settlement_providers.dart';
import '../../widgets/common/error_widget.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/expenses/expense_list_tile.dart';
import '../../widgets/settlements/debt_card.dart';

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
              onPressed: () =>
                  context.push('/groups/${group.id}/edit'),
            ),
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              onPressed: () => context.push('/groups/${group.id}/debts'),
              tooltip: 'Xem số dư',
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
          itemBuilder: (ctx, i) => ExpenseListTile(
            expense: expenses[i],
            members: members,
            onTap: () => context.push(
              '/groups/${group.id}/expenses/${expenses[i].id}/edit',
            ),
          ),
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
              trailing: member.isMe
                  ? const Chip(label: Text('Tôi'))
                  : null,
            );
          },
        );
      },
      loading: () => const AppLoadingWidget(),
      error: (e, _) => AppErrorWidget(message: e.toString()),
    );
  }
}
