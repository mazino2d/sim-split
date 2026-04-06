import 'package:flutter/material.dart';

import '../../../domain/entities/debt.dart';

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
    final amount =
        (debt.amountCents / 100).toStringAsFixed(0);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        title: Text('${debt.from.name} nợ ${debt.to.name}'),
        subtitle: Text(
          '$amount $currencyCode',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16),
        ),
        trailing: FilledButton(
          onPressed: onSettle,
          child: const Text('Trả'),
        ),
      ),
    );
  }
}
