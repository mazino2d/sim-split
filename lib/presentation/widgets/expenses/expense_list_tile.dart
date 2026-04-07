import 'package:flutter/material.dart';

import '../../../core/utils/money_formatter.dart';
import '../../../domain/entities/expense.dart';
import '../../../domain/entities/member.dart';

class ExpenseListTile extends StatelessWidget {
  const ExpenseListTile({
    super.key,
    required this.expense,
    required this.members,
    this.onTap,
  });

  final Expense expense;
  final List<Member> members;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final paidBy = members.where((m) => m.id == expense.paidByMemberId).firstOrNull;
    final amountDisplay = formatMoney(expense.amountCents, expense.currencyCode);

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
        paidBy != null ? '${paidBy.name} đã trả' : '',
        style: const TextStyle(color: Colors.grey),
      ),
      trailing: Text(
        amountDisplay,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      onTap: onTap,
    );
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
