import 'package:flutter/material.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/debt.dart';

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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        title: Text(l10n.owes(debt.from.name, debt.to.name)),
        subtitle: Text(
          formatMoney(debt.amountCents, currencyCode),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        trailing: FilledButton(
          onPressed: onSettle,
          child: Text(l10n.settle),
        ),
      ),
    );
  }
}
