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

/// Whether [currencyCode] has a decimal subunit (USD, EUR…) as opposed to a
/// zero-decimal currency (VND, JPY…) whose amounts are entered as whole units.
bool currencyHasDecimals(String currencyCode) => _hasDecimals(currencyCode);

/// The smallest amount (in stored cents) a user can enter for [currencyCode]:
/// 1 for decimal currencies, 100 (one whole unit) for zero-decimal ones.
int inputStepCents(String currencyCode) => _hasDecimals(currencyCode) ? 1 : 100;

final _digitsOnly = RegExp(r'^\d+$');
final _groupedThousands = RegExp(r'^\d{1,3}([.,]\d{3})+$');

/// Parses user-entered money text into stored integer cents.
///
/// - Zero-decimal currencies (VND, JPY…): integer units, thousands separators
///   (`.`, `,`, spaces) accepted. `"100.000"` VND → `10000000`.
/// - Decimal currencies (USD, EUR, SGD, THB…): up to 2 decimals, `.` or `,`
///   as decimal separator, optional thousands grouping.
///   `"12.50"` / `"12,5"` USD → `1250`; `"1,234.56"` → `123456`.
///
/// Returns `null` when the input is empty, negative or malformed.
int? parseMoneyToCents(String input, String currencyCode) {
  final text = input.replaceAll(RegExp(r'[\s\u00A0]'), '');
  if (text.isEmpty) return null;

  if (!_hasDecimals(currencyCode)) {
    final int? units;
    if (_digitsOnly.hasMatch(text)) {
      units = int.tryParse(text);
    } else if (_groupedThousands.hasMatch(text) &&
        !(text.contains('.') && text.contains(','))) {
      units = int.tryParse(text.replaceAll(RegExp(r'[.,]'), ''));
    } else {
      units = null;
    }
    return units == null ? null : units * 100;
  }

  if (!RegExp(r'^[\d.,]+$').hasMatch(text)) return null;

  final lastDot = text.lastIndexOf('.');
  final lastComma = text.lastIndexOf(',');
  final sepIndex = lastDot > lastComma ? lastDot : lastComma;

  String wholePart;
  var fracPart = '';
  if (sepIndex < 0) {
    wholePart = text;
  } else {
    final sep = text[sepIndex];
    final otherSep = sep == '.' ? ',' : '.';
    final before = text.substring(0, sepIndex);
    final after = text.substring(sepIndex + 1);
    final sepCount = sep.allMatches(text).length;
    final isDecimal =
        sepCount == 1 && after.length <= 2 && !before.contains(sep);
    if (isDecimal) {
      wholePart = before;
      fracPart = after;
      // Remaining separators in the whole part must be thousands grouping.
      if (wholePart.contains(otherSep)) {
        if (!_groupedThousands.hasMatch(wholePart)) return null;
        wholePart = wholePart.replaceAll(otherSep, '');
      }
    } else if (_groupedThousands.hasMatch(text) &&
        !(text.contains('.') && text.contains(','))) {
      wholePart = text.replaceAll(sep, '');
    } else {
      return null;
    }
  }

  if (wholePart.isEmpty) wholePart = '0';
  if (!_digitsOnly.hasMatch(wholePart)) return null;
  if (fracPart.isNotEmpty && !_digitsOnly.hasMatch(fracPart)) return null;

  final whole = int.tryParse(wholePart);
  if (whole == null) return null;
  final frac = fracPart.isEmpty ? 0 : int.parse(fracPart.padRight(2, '0'));
  return whole * 100 + frac;
}

/// Formats stored cents as an editable input string that
/// [parseMoneyToCents] round-trips.
///
/// - Zero-decimal currencies: whole units with `.` thousands grouping
///   (rounded to the nearest unit). `10000000` VND → `"100.000"`.
/// - Decimal currencies: plain number with `.` decimal separator and no
///   grouping; decimals are omitted when zero. `1250` → `"12.50"`,
///   `1200` → `"12"`.
String formatCentsForInput(int cents, String currencyCode) {
  final negative = cents < 0;
  final abs = cents.abs();
  final String body;
  if (_hasDecimals(currencyCode)) {
    final whole = abs ~/ 100;
    final frac = abs % 100;
    body = frac == 0 ? '$whole' : '$whole.${frac.toString().padLeft(2, '0')}';
  } else {
    body = _addThousandsDots((abs + 50) ~/ 100);
  }
  return negative ? '-$body' : body;
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
