/// Formats an amount stored as integer cents into a human-readable string
/// with thousands separators and a currency symbol.
///
/// Convention: amountCents is always the stored value * 100.
/// For VND (no subunit), 100,000 VND is stored as 10,000,000 cents.
String formatMoney(int amountCents, String currencyCode) {
  // For currencies without decimal subunits (VND, JPY, KRW…) we still
  // divide by 100 since the app stores everything *100 for consistency.
  final isDecimalCurrency = _hasDecimals(currencyCode);
  final symbol = _currencySymbol(currencyCode);

  if (isDecimalCurrency) {
    final whole = amountCents ~/ 100;
    final frac = (amountCents % 100).abs();
    final wholeFormatted = _addThousandsDots(whole);
    return '$wholeFormatted,${frac.toString().padLeft(2, '0')} $symbol';
  } else {
    final amount = amountCents ~/ 100;
    final formatted = _addThousandsDots(amount);
    return '$formatted $symbol';
  }
}

/// Short form: same as [formatMoney] but omits the symbol, useful for inputs.
String formatAmount(int amountCents, String currencyCode) {
  final isDecimalCurrency = _hasDecimals(currencyCode);
  if (isDecimalCurrency) {
    final whole = amountCents ~/ 100;
    final frac = (amountCents % 100).abs();
    return '${_addThousandsDots(whole)},${frac.toString().padLeft(2, '0')}';
  } else {
    return _addThousandsDots(amountCents ~/ 100);
  }
}

/// Adds dot-separated thousands grouping (Vietnamese convention).
/// e.g. 1000000 → "1.000.000"
String _addThousandsDots(int amount) {
  final s = amount.abs().toString();
  final buf = StringBuffer();
  final start = s.length % 3;
  if (start > 0) buf.write(s.substring(0, start));
  for (var i = start; i < s.length; i += 3) {
    if (buf.isNotEmpty) buf.write('.');
    buf.write(s.substring(i, i + 3));
  }
  if (amount < 0) return '-${buf.toString()}';
  return buf.toString();
}

bool _hasDecimals(String code) {
  const noDecimal = {'VND', 'JPY', 'KRW', 'IDR', 'HUF', 'CLP', 'ISK'};
  return !noDecimal.contains(code.toUpperCase());
}

String _currencySymbol(String code) => switch (code.toUpperCase()) {
      'VND' => '₫',
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      'JPY' => '¥',
      'KRW' => '₩',
      'THB' => '฿',
      'SGD' => 'S\$',
      'AUD' => 'A\$',
      'CAD' => 'C\$',
      _ => code,
    };
