import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/relative_time.dart';
import 'package:simsplit/presentation/utils/expense_category_ui.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';
import 'package:simsplit/presentation/widgets/common/member_avatar.dart';
import 'package:simsplit/presentation/widgets/common/money_text.dart';
import 'package:simsplit/presentation/widgets/common/section_label.dart';

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final expensesAsync = ref.watch(expenseListProvider(groupId));
    final membersAsync = ref.watch(memberListProvider(groupId));
    final groupAsync = ref.watch(groupDetailProvider(groupId));

    if (expensesAsync.isLoading ||
        membersAsync.isLoading ||
        groupAsync.isLoading) {
      return const Scaffold(body: AppLoadingWidget());
    }

    final expense =
        (expensesAsync.value ?? []).where((e) => e.id == expenseId).firstOrNull;

    if (expense == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.viewExpense)),
        body: Center(child: Text(l10n.errorNotFound)),
      );
    }

    final members = membersAsync.value ?? [];
    final currencyCode = groupAsync.value?.currencyCode ?? expense.currencyCode;
    final paidBy =
        members.where((m) => m.id == expense.paidByMemberId).firstOrNull;

    final locale = Localizations.localeOf(context).toLanguageTag();
    final dateLabel = DateFormat('EEEE, d MMM yyyy', locale)
        .format(expense.expenseDate.toLocal());
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );

    // Who added and last edited it, by their member in this group (AC18).
    String? nameOf(String? uid) {
      final member = members.where((m) => m.linkedUid == uid).firstOrNull;
      if (uid == null || member == null) return null;
      return member.isMe ? '${member.name} ${l10n.meLabel}' : member.name;
    }

    final addedBy = nameOf(expense.createdBy);
    final editedBy = expense.updatedAt.isAfter(expense.createdAt)
        ? nameOf(expense.updatedBy)
        : null;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.editExpense,
            onPressed: () => context.push(
              '/groups/$groupId/expenses/$expenseId/edit',
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CategoryTile(category: expense.category, size: 52),
                const SizedBox(height: 16),
                Text(expense.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MoneyText(
                    expense.amountCents,
                    currencyCode,
                    style: theme.textTheme.displaySmall,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    if (paidBy != null)
                      l10n.paidByLabel(paidBy.isMe
                          ? '${paidBy.name} ${l10n.meLabel}'
                          : paidBy.name),
                    dateLabel,
                  ].join(' · '),
                  style: muted,
                ),
                if (addedBy != null) ...[
                  const SizedBox(height: 4),
                  Text(l10n.addedBy(addedBy), style: muted),
                ],
                if (editedBy != null)
                  Text(
                    l10n.editedBy(
                      editedBy,
                      relativeTime(expense.updatedAt, l10n, locale),
                    ),
                    style: muted,
                  ),
              ],
            ),
          ),
          SectionLabel(l10n.splitBreakdown),
          for (final split in expense.splits)
            if (members.where((m) => m.id == split.memberId).firstOrNull
                case final member?)
              ListTile(
                leading: MemberAvatar(member: member, size: 36),
                title: Text(
                  member.isMe ? '${member.name} ${l10n.meLabel}' : member.name,
                ),
                trailing: MoneyText(
                  split.amountCents,
                  currencyCode,
                  style: theme.textTheme.titleSmall,
                ),
              ),
        ],
      ),
    );
  }
}
