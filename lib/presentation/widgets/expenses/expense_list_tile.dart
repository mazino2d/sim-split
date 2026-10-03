import 'package:flutter/material.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/expense_category_ui.dart';
import 'package:simsplit/presentation/widgets/common/money_text.dart';

class ExpenseListTile extends StatelessWidget {
  const ExpenseListTile({
    super.key,
    required this.expense,
    required this.members,
    this.meMember,
    this.onTap,
  });

  final Expense expense;
  final List<Member> members;

  /// The member marked as "me" in this group. If null, the "my share" line
  /// is omitted.
  final Member? meMember;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final paidBy =
        members.where((m) => m.id == expense.paidByMemberId).firstOrNull;
    final effect = _myEffectCents();

    final payer = paidBy == null
        ? null
        : l10n.paidByLabel(
            paidBy.isMe ? '${paidBy.name} ${l10n.meLabel}' : paidBy.name);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gutter,
          vertical: 10,
        ),
        child: Row(
          children: [
            CategoryTile(category: expense.category),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (payer != null) payer,
                      l10n.peopleCount(expense.splits.length),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(
                  expense.amountCents,
                  expense.currencyCode,
                  style: theme.textTheme.titleSmall,
                ),
                if (effect != null && effect != 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    effect > 0
                        ? l10n.shareYouGet(
                            formatMoney(effect, expense.currencyCode))
                        : l10n.shareYouOwe(
                            formatMoney(-effect, expense.currencyCode)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.money.forSign(effect, cs),
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// How this expense moves "my" balance: positive when I paid for others,
  /// negative when someone else paid for me, null when I'm not in the group.
  int? _myEffectCents() {
    final me = meMember;
    if (me == null) return null;
    final myShare = expense.splits
            .where((s) => s.memberId == me.id)
            .firstOrNull
            ?.amountCents ??
        0;
    return expense.paidByMemberId == me.id
        ? expense.amountCents - myShare
        : -myShare;
  }
}
