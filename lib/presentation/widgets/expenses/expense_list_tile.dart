import 'package:flutter/material.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/member.dart';

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

  /// The member marked as "me" in this group. If null, the "my share" row
  /// is omitted from the trailing column.
  final Member? meMember;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final paidBy =
        members.where((m) => m.id == expense.paidByMemberId).firstOrNull;
    final amountDisplay =
        formatMoney(expense.amountCents, expense.currencyCode);

    // Compute "my share"
    final myShare = _computeMyShare();

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          _categoryIcon(expense.category),
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(expense.title),
      subtitle: Text(
        paidBy != null ? l10n.paidByLabel(paidBy.name) : '',
        style: const TextStyle(color: Colors.grey),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            amountDisplay,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (myShare != null) ...[
            const SizedBox(height: 2),
            Text(
              myShare.label,
              style: TextStyle(
                fontSize: 12,
                color: myShare.color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }

  _MyShare? _computeMyShare() {
    final me = meMember;
    if (me == null) return null;

    final mySplit =
        expense.splits.where((s) => s.memberId == me.id).firstOrNull;
    final myShareCents = mySplit?.amountCents ?? 0;
    if (myShareCents == 0) return null;

    final label = formatMoney(myShareCents, expense.currencyCode);

    if (expense.paidByMemberId == me.id) {
      // I paid — I'm owed back my net (total - my split)
      final owedBack = expense.amountCents - myShareCents;
      if (owedBack <= 0) return null;
      return _MyShare('+${formatMoney(owedBack, expense.currencyCode)}', Colors.green);
    } else {
      // Someone else paid — I owe my share
      return _MyShare('-$label', Colors.red);
    }
  }

  IconData _categoryIcon(ExpenseCategory category) => switch (category) {
        ExpenseCategory.food => Icons.restaurant,
        ExpenseCategory.transport => Icons.directions_car,
        ExpenseCategory.accommodation => Icons.hotel,
        ExpenseCategory.entertainment => Icons.movie,
        ExpenseCategory.shopping => Icons.shopping_bag,
        ExpenseCategory.health => Icons.local_hospital,
        ExpenseCategory.other => Icons.receipt_long,
      };
}

class _MyShare {
  const _MyShare(this.label, this.color);
  final String label;
  final Color color;
}
