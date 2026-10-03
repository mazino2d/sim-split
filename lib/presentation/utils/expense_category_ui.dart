import 'package:flutter/material.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/expense.dart';

/// Icon and localized label for each [ExpenseCategory].
extension ExpenseCategoryUi on ExpenseCategory {
  IconData get icon => switch (this) {
        ExpenseCategory.food => Icons.restaurant_rounded,
        ExpenseCategory.transport => Icons.directions_car_rounded,
        ExpenseCategory.accommodation => Icons.bed_rounded,
        ExpenseCategory.entertainment => Icons.celebration_rounded,
        ExpenseCategory.shopping => Icons.shopping_bag_rounded,
        ExpenseCategory.health => Icons.medical_services_rounded,
        ExpenseCategory.other => Icons.receipt_long_rounded,
      };

  String label(AppLocalizations l10n) => switch (this) {
        ExpenseCategory.food => l10n.categoryFood,
        ExpenseCategory.transport => l10n.categoryTransport,
        ExpenseCategory.accommodation => l10n.categoryAccommodation,
        ExpenseCategory.entertainment => l10n.categoryEntertainment,
        ExpenseCategory.shopping => l10n.categoryShopping,
        ExpenseCategory.health => l10n.categoryHealth,
        ExpenseCategory.other => l10n.categoryOther,
      };
}

/// Rounded-square tile showing a category icon, used in lists and pickers.
class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.category, this.size = 44});

  final ExpenseCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(category.icon, size: size * 0.5, color: cs.onSurface),
    );
  }
}
