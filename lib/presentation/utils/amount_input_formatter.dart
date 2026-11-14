import 'package:flutter/services.dart';
import 'package:simsplit/core/utils/money_formatter.dart';

/// Live thousands grouping for zero-decimal currencies (VND: `1.250.000`),
/// so long amounts can be read while typing. Decimal currencies keep free
/// input limited to digits and one separator.
class AmountInputFormatter extends TextInputFormatter {
  AmountInputFormatter(this.currencyCode);

  final String currencyCode;

  static const _maxDigits = 12;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (currencyHasDecimals(currencyCode)) {
      final ok = RegExp(r'^\d{0,12}([.,]\d{0,2})?$').hasMatch(newValue.text);
      return ok ? newValue : oldValue;
    }

    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > _maxDigits) return oldValue;
    final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (trimmed.isEmpty) return const TextEditingValue();

    // Keep the caret after the same number of digits it was after.
    final caret = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsBeforeCaret = newValue.text
        .substring(0, caret)
        .replaceAll(RegExp(r'\D'), '')
        .length
        .clamp(0, trimmed.length);
    final leadingDropped = digits.length - trimmed.length;

    final buf = StringBuffer();
    var offset = 0;
    var seen = 0;
    final target =
        (digitsBeforeCaret - leadingDropped).clamp(0, trimmed.length);
    for (var i = 0; i < trimmed.length; i++) {
      if (i > 0 && (trimmed.length - i) % 3 == 0) buf.write('.');
      buf.write(trimmed[i]);
      seen++;
      if (seen == target) offset = buf.length;
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: target == 0 ? 0 : offset),
    );
  }
}
