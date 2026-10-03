import 'package:flutter/material.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/widgets/common/member_avatar.dart';
import 'package:simsplit/presentation/widgets/common/money_text.dart';

/// One suggested transfer: "From → To", the amount, and a Settle action.
class DebtCard extends StatelessWidget {
  const DebtCard({
    super.key,
    required this.debt,
    required this.currencyCode,
    this.onSettle,
  });

  final Debt debt;
  final String currencyCode;
  final VoidCallback? onSettle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    String name(Member member) =>
        member.isMe ? '${member.name} ${l10n.meLabel}' : member.name;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          MemberAvatar(member: debt.from, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name(debt.from),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 16, color: cs.onSurfaceVariant),
                    ),
                    Flexible(
                      child: Text(
                        name(debt.to),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                MoneyText(
                  debt.amountCents,
                  currencyCode,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          if (onSettle != null) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onSettle,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: Text(l10n.settle),
            ),
          ],
        ],
      ),
    );
  }
}
