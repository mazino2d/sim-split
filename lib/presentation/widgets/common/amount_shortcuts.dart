import 'package:flutter/material.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/amount_suggestions.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

/// Chips under an amount field for currencies whose amounts end in many
/// zeros (VND…): the typed number in thousands, and a "000" key (#114).
/// Shows nothing for other currencies.
class AmountShortcuts extends StatelessWidget {
  const AmountShortcuts({
    super.key,
    required this.controller,
    required this.currencyCode,
    this.alignment = WrapAlignment.start,
  });

  final TextEditingController controller;
  final String currencyCode;
  final WrapAlignment alignment;

  void _set(int cents) {
    final text = formatCentsForInput(cents, currencyCode);
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!hasAmountShortcuts(currencyCode)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final typed = parseMoneyToCents(controller.text, currencyCode);
        final appended = appendThousand(typed, currencyCode);
        return Wrap(
          alignment: alignment,
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final cents in amountSuggestions(typed, currencyCode))
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(formatMoney(cents, currencyCode)),
                onPressed: context.tracked(
                    TelemetryEvent.tapAmountSuggestion, () => _set(cents)),
              ),
            // Always shown (disabled when empty) so the row doesn't jump.
            ActionChip(
              visualDensity: VisualDensity.compact,
              tooltip: l10n.appendThousand,
              label: const Text('000'),
              onPressed: context.tracked(TelemetryEvent.tapAppendThousand,
                  appended == null ? null : () => _set(appended)),
            ),
          ],
        );
      },
    );
  }
}
