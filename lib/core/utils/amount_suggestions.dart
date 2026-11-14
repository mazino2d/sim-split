/// Shortcuts for typing amounts in currencies whose amounts almost always
/// end in three or more zeros (#114): typing `45` in a VND group suggests
/// 45.000, 450.000 and 4.500.000, and a "000" key appends three zeros.
///
/// Driven by the currency, never by the app language. Amounts are stored
/// cents (amount × 100), so suggestions are exact integers.
library;

/// The smallest everyday amount, in whole units, per currency. Currencies
/// not listed get no shortcuts.
const _typicalStep = {'VND': 1000, 'IDR': 1000, 'KRW': 1000};

/// The amount field accepts at most 12 digits.
const _maxUnits = 999999999999;

/// Whether [currencyCode] gets amount shortcuts.
bool hasAmountShortcuts(String currencyCode) =>
    _typicalStep.containsKey(currencyCode.toUpperCase());

/// Amounts (in cents) to offer for a typed amount of [typedCents]: the typed
/// number times 1 000, 10 000 and 100 000. Only while the typed number is
/// still below the currency's step, so the suggestions go away once the
/// user has typed the zeros.
List<int> amountSuggestions(int? typedCents, String currencyCode) {
  final step = _typicalStep[currencyCode.toUpperCase()];
  if (step == null || typedCents == null || typedCents <= 0) return const [];
  final units = typedCents ~/ 100;
  if (units >= step) return const [];
  return [
    for (final factor in [step, step * 10, step * 100])
      if (units * factor <= _maxUnits) units * factor * 100,
  ];
}

/// [typedCents] with three zeros appended, or null when there is nothing to
/// append to or the result wouldn't fit the field.
int? appendThousand(int? typedCents, String currencyCode) {
  if (!hasAmountShortcuts(currencyCode)) return null;
  if (typedCents == null || typedCents <= 0) return null;
  final units = typedCents ~/ 100 * 1000;
  return units > _maxUnits ? null : units * 100;
}
