/// Represents an amount of money as integer cents to avoid floating-point errors.
/// VND has no subunit so amounts are stored × 100 for schema uniformity with USD.
class Money {
  const Money({required this.amountCents, required this.currency});

  /// Creates Money from a double display value (e.g. 50000 VND → amountCents = 5000000).
  factory Money.fromDisplay(double displayAmount, String currency) {
    return Money(
      amountCents: (displayAmount * 100).round(),
      currency: currency,
    );
  }

  /// Integer cents. Always >= 0.
  final int amountCents;

  /// ISO 4217 currency code, e.g. 'VND', 'USD'.
  final String currency;

  /// Display value for UI (amountCents / 100).
  double get displayAmount => amountCents / 100;

  bool get isZero => amountCents == 0;
  bool get isPositive => amountCents > 0;

  Money operator +(Money other) {
    assert(currency == other.currency, 'Cannot add different currencies');
    return Money(amountCents: amountCents + other.amountCents, currency: currency);
  }

  Money operator -(Money other) {
    assert(currency == other.currency, 'Cannot subtract different currencies');
    return Money(amountCents: amountCents - other.amountCents, currency: currency);
  }

  Money abs() => Money(amountCents: amountCents.abs(), currency: currency);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Money &&
          other.amountCents == amountCents &&
          other.currency == currency);

  @override
  int get hashCode => Object.hash(amountCents, currency);

  @override
  String toString() => '$amountCents $currency (cents)';
}
