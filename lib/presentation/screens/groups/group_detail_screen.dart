import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/presentation/notifiers/expense_notifier.dart';
import 'package:simsplit/presentation/notifiers/settlement_notifier.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/widgets/common/empty_state.dart';
import 'package:simsplit/presentation/widgets/common/error_widget.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';
import 'package:simsplit/presentation/widgets/common/member_avatar.dart';
import 'package:simsplit/presentation/widgets/common/money_text.dart';
import 'package:simsplit/presentation/widgets/common/section_label.dart';
import 'package:simsplit/presentation/widgets/expenses/expense_list_tile.dart';
import 'package:simsplit/presentation/widgets/settlements/debt_card.dart';
import 'package:simsplit/presentation/widgets/settlements/settlement_list_tile.dart';

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
        appBar: AppBar(),
        body: AppErrorWidget(
          error: e,
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
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _addExpense() {
    final members = ref.read(memberListProvider(widget.group.id)).value ?? [];
    if (members.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.noMembersAddExpenseHint),
          action: SnackBarAction(
            label: l10n.addMember,
            onPressed: () => context.push('/groups/${widget.group.id}/edit'),
          ),
        ),
      );
      return;
    }
    context.push('/groups/${widget.group.id}/expenses/add');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final group = widget.group;
    final showFab = _tabController.index == 0;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            title: Text(
              '${group.emoji ?? ''} ${group.name}'.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: l10n.editGroup,
                onPressed: () => context.push('/groups/${group.id}/edit'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(child: _GroupHeader(group: group)),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: l10n.expenses),
                  Tab(text: l10n.settlements),
                ],
              ),
              Theme.of(context).colorScheme.surface,
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _ExpensesTab(group: group, onAddExpense: _addExpense),
            _SettleTab(group: group),
          ],
        ),
      ),
      floatingActionButton: AnimatedScale(
        scale: showFab ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: FloatingActionButton.extended(
          onPressed: showFab ? _addExpense : null,
          icon: const Icon(Icons.add),
          label: Text(l10n.addExpense),
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate(this.tabBar, this.background);

  final TabBar tabBar;
  final Color background;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: background, child: tabBar);

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar || background != oldDelegate.background;
}

// ── Header ──────────────────────────────────────────────────────────────────

/// Total spent by the group, plus "my" share and net balance.
class _GroupHeader extends ConsumerWidget {
  const _GroupHeader({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final expenses = ref.watch(expenseListProvider(group.id)).value ?? [];
    final members = ref.watch(memberListProvider(group.id)).value ?? [];
    final me = members.where((m) => m.isMe).firstOrNull;

    final total = expenses.fold<int>(0, (sum, e) => sum + e.amountCents);
    final myShare = me == null
        ? 0
        : expenses.fold<int>(
            0,
            (sum, e) =>
                sum +
                (e.splits
                        .where((s) => s.memberId == me.id)
                        .firstOrNull
                        ?.amountCents ??
                    0),
          );
    final myNet = me == null
        ? null
        : ref
            .watch(debtSummaryProvider(group.id, group.currencyCode))
            .value
            ?.balances
            .where((b) => b.member.id == me.id)
            .firstOrNull
            ?.netAmountCents;

    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );

    Widget stat(String label, Widget value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: muted),
              const SizedBox(height: 2),
              value,
            ],
          ),
        );

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppTheme.gutter, 4, AppTheme.gutter, 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.totalSpent, style: muted),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyText(
                total,
                group.currencyCode,
                style: theme.textTheme.headlineMedium,
              ),
            ),
            if (me != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  stat(
                    l10n.yourShare,
                    MoneyText(myShare, group.currencyCode,
                        style: theme.textTheme.titleSmall),
                  ),
                  const SizedBox(width: 16),
                  stat(
                    (myNet ?? 0) > 0
                        ? l10n.totalOwedToYou
                        : (myNet ?? 0) < 0
                            ? l10n.totalYouOwe
                            : l10n.statusSettled,
                    MoneyText(
                      (myNet ?? 0).abs(),
                      group.currencyCode,
                      color: context.money.forSign(myNet ?? 0, cs),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Expenses Tab ─────────────────────────────────────────────────────────────

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab({required this.group, required this.onAddExpense});

  final Group group;
  final VoidCallback onAddExpense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final expensesAsync = ref.watch(expenseListProvider(group.id));
    final members = ref.watch(memberListProvider(group.id)).value ?? [];
    final meMember = members.where((m) => m.isMe).firstOrNull;

    return expensesAsync.when(
      data: (expenses) {
        if (expenses.isEmpty) {
          return members.isEmpty
              ? EmptyState(
                  icon: Icons.group_add_outlined,
                  title: l10n.addMembersFirst,
                  actionLabel: l10n.addMember,
                  onAction: () => context.push('/groups/${group.id}/edit'),
                )
              : EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: l10n.noExpenses,
                  message: l10n.noExpensesHint,
                  actionLabel: l10n.addExpense,
                  onAction: onAddExpense,
                );
        }

        // Group by day, newest first.
        final byDay = <DateTime, List<Expense>>{};
        for (final e in expenses) {
          final d = e.expenseDate.toLocal();
          byDay.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(e);
        }
        final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

        return CustomScrollView(
          slivers: [
            for (final day in days) ...[
              SliverToBoxAdapter(
                child: SectionLabel(
                  _dayLabel(context, day),
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.gutter, 20, AppTheme.gutter, 4),
                  trailing: MoneyText(
                    byDay[day]!.fold<int>(0, (s, e) => s + e.amountCents),
                    group.currencyCode,
                  ),
                ),
              ),
              SliverList.list(
                children: [
                  for (final expense in byDay[day]!)
                    _SwipeableExpenseTile(
                      expense: expense,
                      members: members,
                      meMember: meMember,
                      group: group,
                    ),
                ],
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
      loading: () => const AppLoadingWidget(),
      error: (e, _) => AppErrorWidget(error: e),
    );
  }

  String _dayLabel(BuildContext context, DateTime date) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (date == today) return l10n.today;
    if (date == today.subtract(const Duration(days: 1))) return l10n.yesterday;
    return DateFormat(
      date.year == now.year ? 'EEEE, d MMM' : 'd MMM yyyy',
      locale,
    ).format(date);
  }
}

// ── Swipeable Expense Tile ────────────────────────────────────────────────────

/// Tap opens the detail; swipe left deletes after confirmation.
class _SwipeableExpenseTile extends ConsumerWidget {
  const _SwipeableExpenseTile({
    required this.expense,
    required this.members,
    required this.meMember,
    required this.group,
  });

  final Expense expense;
  final List<Member> members;
  final Member? meMember;
  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Dismissible(
      key: ValueKey('expense-${expense.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final confirmed = await _confirmDestructive(
          context,
          title: l10n.deleteExpenseConfirmTitle,
          message: l10n.deleteConfirmMessage,
        );
        if (!confirmed || !context.mounted) return false;
        final messenger = ScaffoldMessenger.of(context);
        final result =
            await ref.read(expenseProvider.notifier).deleteExpense(expense.id);
        result.fold(
          (failure) => messenger.showSnackBar(
            SnackBar(content: Text(failureMessage(failure, l10n))),
          ),
          (_) {},
        );
        return false;
      },
      background: const _DeleteBackground(),
      child: ExpenseListTile(
        expense: expense,
        members: members,
        meMember: meMember,
        onTap: () => context.push('/groups/${group.id}/expenses/${expense.id}'),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.error,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 24),
          child: Icon(Icons.delete_outline, color: cs.onError),
        ),
      ),
    );
  }
}

Future<bool> _confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dCtx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dCtx).colorScheme.error,
            foregroundColor: Theme.of(dCtx).colorScheme.onError,
            minimumSize: const Size(64, 44),
          ),
          onPressed: () => Navigator.pop(dCtx, true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  return confirmed == true;
}

// ── Settle Tab ───────────────────────────────────────────────────────────────

/// Everything about paying back in one place: the simplified transfers with a
/// Settle action, each member's net balance, and the payment history.
class _SettleTab extends ConsumerWidget {
  const _SettleTab({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final debtAsync =
        ref.watch(debtSummaryProvider(group.id, group.currencyCode));
    final settlementsAsync = ref.watch(settlementListProvider(group.id));
    final members = ref.watch(memberListProvider(group.id)).value ?? [];

    return debtAsync.when(
      data: (summary) {
        final settlements = settlementsAsync.value ?? const <Settlement>[];
        return ListView(
          padding: const EdgeInsets.only(bottom: 48),
          children: [
            SectionLabel(l10n.whoPaysWhom),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
              child: summary.suggestions.isEmpty
                  ? const _SettledUpCard()
                  : _Panel(
                      children: [
                        for (final debt in summary.suggestions)
                          DebtCard(
                            debt: debt,
                            currencyCode: group.currencyCode,
                            onSettle: () => _openSettle(context, debt),
                          ),
                      ],
                    ),
            ),
            if (summary.balances.isNotEmpty) ...[
              SectionLabel(l10n.balances),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
                child: _Panel(
                  children: [
                    for (final balance in summary.balances)
                      _MemberBalanceRow(
                        member: balance.member,
                        netCents: balance.netAmountCents,
                        maxAbsCents: summary.balances.fold<int>(
                          0,
                          (m, b) => b.netAmountCents.abs() > m
                              ? b.netAmountCents.abs()
                              : m,
                        ),
                        currencyCode: group.currencyCode,
                      ),
                  ],
                ),
              ),
            ],
            SectionLabel(l10n.settlementHistory),
            if (settlementsAsync.isLoading)
              const AppLoadingWidget()
            else if (settlements.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
                child: Text(
                  l10n.noSettlements,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              )
            else
              for (final settlement in settlements)
                _SwipeableSettlementTile(
                  settlement: settlement,
                  members: members,
                ),
          ],
        );
      },
      loading: () => const AppLoadingWidget(),
      error: (e, _) => AppErrorWidget(
        error: e,
        onRetry: () =>
            ref.invalidate(debtSummaryProvider(group.id, group.currencyCode)),
      ),
    );
  }

  void _openSettle(BuildContext context, Debt debt) => context.push(
        '/groups/${group.id}/settle',
        extra: {
          'fromMemberId': debt.from.id,
          'toMemberId': debt.to.id,
          'amountCents': debt.amountCents,
        },
      );
}

/// Rounded surface grouping rows, separated by hairlines.
class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            child,
          ],
        ],
      ),
    );
  }
}

class _SettledUpCard extends StatelessWidget {
  const _SettledUpCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: context.money.positive),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.settledUp,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// A member's net balance with a centred bar: right of centre when they are
/// owed, left of centre when they owe, scaled to the largest balance.
class _MemberBalanceRow extends StatelessWidget {
  const _MemberBalanceRow({
    required this.member,
    required this.netCents,
    required this.maxAbsCents,
    required this.currencyCode,
  });

  final Member member;
  final int netCents;
  final int maxAbsCents;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = context.money.forSign(netCents, cs);
    final fraction = maxAbsCents == 0 ? 0.0 : netCents.abs() / maxAbsCents;

    Widget half({required bool active, required Alignment from}) => Expanded(
          child: Align(
            alignment: from,
            child: FractionallySizedBox(
              widthFactor: active ? fraction : 0,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          MemberAvatar(member: member, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        member.isMe
                            ? '${member.name} ${l10n.meLabel}'
                            : member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    MoneyText(
                      netCents,
                      currencyCode,
                      signed: true,
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      half(active: netCents < 0, from: Alignment.centerRight),
                      half(active: netCents > 0, from: Alignment.centerLeft),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Settlement history row. Swipe left to delete a payment recorded by
/// mistake; there is no edit — delete and record it again instead.
class _SwipeableSettlementTile extends ConsumerWidget {
  const _SwipeableSettlementTile({
    required this.settlement,
    required this.members,
  });

  final Settlement settlement;
  final List<Member> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Dismissible(
      key: ValueKey('settlement-${settlement.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final confirmed = await _confirmDestructive(
          context,
          title: l10n.deleteSettlementConfirmTitle,
          message: l10n.deleteSettlementConfirmMessage,
        );
        if (!confirmed || !context.mounted) return false;
        final messenger = ScaffoldMessenger.of(context);
        final result = await ref
            .read(settlementProvider.notifier)
            .deleteSettlement(settlement.id);
        result.fold(
          (failure) => messenger.showSnackBar(
            SnackBar(content: Text(failureMessage(failure, l10n))),
          ),
          (_) {},
        );
        return false;
      },
      background: const _DeleteBackground(),
      child: SettlementListTile(settlement: settlement, members: members),
    );
  }
}
