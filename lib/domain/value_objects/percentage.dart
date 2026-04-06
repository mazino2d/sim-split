/// Validated percentage value in range [0, 100].
/// Stored as integer × 100 (e.g. 33.33% → 3333) to avoid floating-point issues.
class Percentage {
  const Percentage._(this._value);

  /// [value] is a percentage × 100 integer (e.g. 3333 = 33.33%).
  factory Percentage.fromScaled(int value) {
    assert(value >= 0 && value <= 10000, 'Percentage must be between 0 and 100');
    return Percentage._(value);
  }

  /// [displayValue] is a double like 33.33.
  factory Percentage.fromDisplay(double displayValue) {
    assert(displayValue >= 0 && displayValue <= 100);
    return Percentage._((displayValue * 100).round());
  }

  final int _value;

  /// Scaled integer value (× 100). Use this for DB storage.
  int get scaled => _value;

  /// Display value 0.0–100.0.
  double get display => _value / 100;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Percentage && other._value == _value);

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => '${display.toStringAsFixed(2)}%';
}
