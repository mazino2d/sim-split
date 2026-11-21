import 'package:flutter/material.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/presentation/utils/member_label.dart';
import 'package:simsplit/presentation/widgets/common/money_text.dart';

/// One suggested transfer: "From → To", then the amount and a Settle action.
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One paragraph that wraps, so long names are never cut (#111).
          Text.rich(
            TextSpan(children: [
              TextSpan(text: debt.from.label(l10n)),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              TextSpan(text: debt.to.label(l10n)),
            ]),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: MoneyText(
                  debt.amountCents,
                  currencyCode,
                  style: theme.textTheme.titleMedium,
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
        ],
      ),
    );
  }
}
