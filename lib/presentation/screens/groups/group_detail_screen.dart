import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/presentation/notifiers/expense_notifier.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/widgets/common/error_widget.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';
import 'package:simsplit/presentation/widgets/expenses/expense_list_tile.dart';
import 'package:simsplit/presentation/widgets/settlements/debt_card.dart';

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

class _GroupDetailBody extends ConsumerStatefulWidget {
  const _GroupDetailBody({required this.group});

  final Group group;

  @override
  ConsumerState<_GroupDetailBody> createState() => _GroupDetailBodyState();
}

class _GroupDetailBodyState extends ConsumerState<_GroupDetailBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final group = widget.group;

    return Scaffold(
      appBar: AppBar(
        title: Text('${group.emoji ?? ''} ${group.name}'.trim()),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/groups/${group.id}/edit'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.expenses),
            Tab(text: l10n.balances),
            Tab(text: l10n.settlements),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ExpensesTab(group: group),
          _BalancesTab(group: group),
          _SettlementsTab(group: group),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: () {
                final members = ref
                    .read(memberListProvider(group.id))
                    .value ?? [];
                if (members.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          AppLocalizations.of(context)!
                              .noMembersAddExpenseHint),
                      action: SnackBarAction(
                        label: AppLocalizations.of(context)!.addMember,
                        onPressed: () => context
                            .push('/groups/${group.id}/edit'),
                      ),
                    ),
                  );
                  return;
                }
                context.push('/groups/${group.id}/expenses/add');
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

// ── Expenses Tab ─────────────────────────────────────────────────────────────

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final expensesAsync = ref.watch(expenseListProvider(group.id));
    final members = ref.watch(memberListProvider(group.id)).value ?? [];
    final meMember = members.where((m) => m.isMe).firstOrNull;

    return expensesAsync.when(
      data: (expenses) {
        if (expenses.isEmpty) {
          return Center(child: Text(l10n.noExpenses));
        }

        // Group by date, sorted newest first
        final grouped = _groupByDate(expenses);
        final dateKeys = grouped.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        // Build flat list: [date header, tile, tile, date header, tile ...]
        final items = <_ListItem>[];
        for (final date in dateKeys) {
          items.add(_DateHeader(date));
          for (final exp in grouped[date]!) {
            items.add(_ExpenseItem(exp));
          }
        }

        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final item = items[i];
            if (item is _DateHeader) {
              return _DateSectionHeader(date: item.date);
            }
            final expense = (item as _ExpenseItem).expense;
            return _SwipeableExpenseTile(
              expense: expense,
              members: members,
              meMember: meMember,
              group: group,
            );
          },
        );
      },
      loading: () => const AppLoadingWidget(),
      error: (e, _) => AppErrorWidget(message: e.toString()),
    );
  }

  Map<DateTime, List<Expense>> _groupByDate(List<Expense> expenses) {
    final map = <DateTime, List<Expense>>{};
    for (final e in expenses) {
      final d = e.expenseDate.toLocal();
      final key = DateTime(d.year, d.month, d.day);
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }
}

// Sealed-ish item types for the flat list
abstract class _ListItem {}

class _DateHeader extends _ListItem {
  _DateHeader(this.date);
  final DateTime date;
}

class _ExpenseItem extends _ListItem {
  _ExpenseItem(this.expense);
  final Expense expense;
}

class _DateSectionHeader extends StatelessWidget {
  const _DateSectionHeader({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    String label;
    if (date == today) {
      label = AppLocalizations.of(context)!.today;
    } else if (date == yesterday) {
      label = AppLocalizations.of(context)!.yesterday;
    } else if (date.year == now.year) {
      label = DateFormat('d MMM', Localizations.localeOf(context).toLanguageTag())
          .format(date);
    } else {
      label = DateFormat('d MMM yyyy', Localizations.localeOf(context).toLanguageTag())
          .format(date);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ── Swipeable Expense Tile ────────────────────────────────────────────────────

class _SwipeableExpenseTile extends ConsumerWidget {
  const _SwipeableExpenseTile({
    required this.expense,
    required this.members,
    required this.meMember,
    required this.group,
  });

  final Expense expense;
  final List members;
  final dynamic meMember;
  final Group group;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.deleteExpenseConfirmTitle),
        content: Text(l10n.deleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(expenseProvider.notifier).deleteExpense(expense.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Dismissible(
      key: ValueKey('expense-${expense.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Right swipe → edit
          await context.push(
            '/groups/${group.id}/expenses/${expense.id}/edit',
          );
        } else {
          // Left swipe → delete with confirmation
          await _confirmDelete(context, ref);
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        color: Colors.blue,
        child: Row(
          children: [
            const Icon(Icons.edit, color: Colors.white),
            const SizedBox(width: 8),
            Text(l10n.edit,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(l10n.delete,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            const Icon(Icons.delete_outline, color: Colors.white),
          ],
        ),
      ),
      child: ExpenseListTile(
        expense: expense,
        members: members.cast(),
        meMember: meMember,
        onTap: () => context.push(
          '/groups/${group.id}/expenses/${expense.id}',
        ),
      ),
    );
  }
}

// ── Balances Tab ─────────────────────────────────────────────────────────────

class _BalancesTab extends ConsumerWidget {
  const _BalancesTab({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtAsync =
        ref.watch(debtSummaryProvider(group.id, group.currencyCode));

    return debtAsync.when(
      data: (summary) {
        if (summary.balances.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(AppLocalizations.of(context)!.noMembers,
                    style: const TextStyle(fontSize: 18, color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  for (final balance in summary.balances)
                    _MemberBalanceTile(
                      balance: balance,
                      currencyCode: group.currencyCode,
                    ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const AppLoadingWidget(),
      error: (e, _) => AppErrorWidget(
        message: e.toString(),
        onRetry: () => ref.invalidate(
            debtSummaryProvider(group.id, group.currencyCode)),
      ),
    );
  }
}

// ── Settlements Tab ───────────────────────────────────────────────────────────

class _SettlementsTab extends ConsumerWidget {
  const _SettlementsTab({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final debtAsync =
        ref.watch(debtSummaryProvider(group.id, group.currencyCode));

    return debtAsync.when(
      data: (summary) {
        if (summary.suggestions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 80, color: Colors.green),
                const SizedBox(height: 16),
                Text(l10n.settledUp,
                    style: const TextStyle(fontSize: 20)),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final debt in summary.suggestions)
              DebtCard(
                debt: debt,
                currencyCode: group.currencyCode,
                onSettle: () => context.push(
                  '/groups/${group.id}/settle',
                  extra: {
                    'fromMemberId': debt.from.id,
                    'toMemberId': debt.to.id,
                    'amountCents': debt.amountCents,
                  },
                ),
              ),
          ],
        );
      },
      loading: () => const AppLoadingWidget(),
      error: (e, _) => AppErrorWidget(
        message: e.toString(),
        onRetry: () => ref.invalidate(
            debtSummaryProvider(group.id, group.currencyCode)),
      ),
    );
  }
}

class _MemberBalanceTile extends StatelessWidget {
  const _MemberBalanceTile({
    required this.balance,
    required this.currencyCode,
  });

  final MemberBalance balance;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final net = balance.netAmountCents;
    final amountStr = formatMoney(net.abs(), currencyCode);
    final color = net > 0
        ? Colors.green
        : net < 0
            ? Colors.red
            : Colors.grey;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Color(balance.member.avatarColorValue),
        child: Text(
          balance.member.emoji ??
              balance.member.name.substring(0, 1).toUpperCase(),
          style: TextStyle(
            color: balance.member.emoji != null ? null : Colors.white,
            fontSize: balance.member.emoji != null ? 18 : 14,
          ),
        ),
      ),
      title: Text(balance.member.name),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${net >= 0 ? '+' : '-'}$amountStr',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
