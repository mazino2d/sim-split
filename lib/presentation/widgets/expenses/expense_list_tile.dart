import 'package:flutter/material.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/member_label.dart';
import 'package:simsplit/presentation/utils/expense_category_ui.dart';
import 'package:simsplit/presentation/widgets/common/money_text.dart';
import 'package:simsplit/presentation/widgets/common/unsynced_mark.dart';

class ExpenseListTile extends StatelessWidget {
  const ExpenseListTile({
    super.key,
    required this.expense,
    required this.members,
    this.meMember,
    this.unsynced = false,
    this.onTap,
  });

  final Expense expense;
  final List<Member> members;

  /// The member marked as "me" in this group. If null, the "my share" line
  /// is omitted.
  final Member? meMember;

  /// Whether the latest change has not reached the cloud yet (AC16).
  final bool unsynced;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final paidBy =
        members.where((m) => m.id == expense.paidByMemberId).firstOrNull;
    final effect = _myEffectCents();

    Widget line(String label, Widget amount, {TextStyle? labelStyle}) =>
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle ??
                      theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 12),
              amount,
            ],
          ),
        );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gutter,
          vertical: 10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CategoryTile(category: expense.category),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          expense.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (unsynced) ...[
                        const SizedBox(width: 6),
                        const UnsyncedMark(),
                      ],
                    ],
                  ),
                  // Payer and total on one line, my effect on the next: each
                  // amount gets its own line so names keep the width (#111).
                  line(
                    paidBy == null ? '' : l10n.tilePaidBy(paidBy.label(l10n)),
                    MoneyText(
                      expense.amountCents,
                      expense.currencyCode,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (effect != null && effect != 0)
                    line(
                      effect > 0 ? l10n.tileYouGet : l10n.tileYouOwe,
                      MoneyText(
                        effect.abs(),
                        expense.currencyCode,
                        color: context.money.forSign(effect, cs),
                        style: theme.textTheme.bodySmall,
                      ),
                      labelStyle: theme.textTheme.bodySmall?.copyWith(
                        color: context.money.forSign(effect, cs),
                      ),
                    ),
                ],
              ),
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
