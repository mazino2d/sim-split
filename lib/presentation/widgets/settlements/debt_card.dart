import 'package:flutter/material.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/member.dart';

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
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // "From" member
            _MemberAvatar(member: debt.from),
            const SizedBox(width: 8),

            // Arrow + amount (center)
            Expanded(
              child: Column(
                children: [
                  Text(
                    formatMoney(debt.amountCents, currencyCode),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 2,
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: colorScheme.outline,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),
            // "To" member
            _MemberAvatar(member: debt.to),

            if (onSettle != null) ...[
              const SizedBox(width: 12),
              FilledButton(
                onPressed: onSettle,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  minimumSize: const Size(0, 36),
                ),
                child: Text(l10n.settle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: Color(member.avatarColorValue),
          child: Text(
            member.name.substring(0, 1).toUpperCase(),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 52,
          child: Text(
            member.name,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}
