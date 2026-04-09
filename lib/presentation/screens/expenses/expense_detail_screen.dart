import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.groupId,
    required this.expenseId,
  });

  final String groupId;
  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final expensesAsync = ref.watch(expenseListProvider(groupId));
    final membersAsync = ref.watch(memberListProvider(groupId));
    final groupAsync = ref.watch(groupDetailProvider(groupId));

    if (expensesAsync.isLoading || membersAsync.isLoading || groupAsync.isLoading) {
      return const Scaffold(body: AppLoadingWidget());
    }

    final expense = (expensesAsync.valueOrNull ?? [])
        .where((e) => e.id == expenseId)
        .firstOrNull;

    if (expense == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.viewExpense)),
        body: Center(child: Text(l10n.errorNotFound)),
      );
    }

    final members = membersAsync.valueOrNull ?? [];
    final group = groupAsync.valueOrNull;
    final currencyCode = group?.currencyCode ?? expense.currencyCode;
    final paidBy = members.where((m) => m.id == expense.paidByMemberId).firstOrNull;

    final locale = Localizations.localeOf(context).toLanguageTag();
    final dateLabel = DateFormat('d MMM yyyy', locale)
        .format(expense.expenseDate.toLocal());

    return Scaffold(
      appBar: AppBar(
        title: Text(expense.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.editExpense,
            onPressed: () => context.push(
              '/groups/$groupId/expenses/$expenseId/edit',
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatMoney(expense.amountCents, currencyCode),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Chip(
                        label: Text(dateLabel,
                            style: const TextStyle(fontSize: 12)),
                        avatar: const Icon(Icons.calendar_today, size: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (paidBy != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          l10n.paidByLabel(
                            paidBy.isMe
                                ? '${paidBy.name} ${l10n.meLabel}'
                                : paidBy.name,
                          ),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Split breakdown
          Text(
            l10n.splitBreakdown,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),

          for (final split in expense.splits) ...[
            _buildSplitRow(context, split.memberId, split.amountCents,
                members, currencyCode, l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildSplitRow(
    BuildContext context,
    String memberId,
    int amountCents,
    List<Member> members,
    String currencyCode,
    AppLocalizations l10n,
  ) {
    final member = members.where((m) => m.id == memberId).firstOrNull;
    if (member == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(member.avatarColorValue),
          child: member.emoji != null
              ? Text(member.emoji!, style: const TextStyle(fontSize: 18))
              : Text(
                  member.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
        ),
        title: Text(
          member.isMe
              ? '${member.name} ${l10n.meLabel}'
              : member.name,
        ),
        trailing: Text(
          formatMoney(amountCents, currencyCode),
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
    );
  }
}
