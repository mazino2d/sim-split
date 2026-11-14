import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/utils/amount_suggestions.dart';

void main() {
  group('amountSuggestions', () {
    test('suggests the typed number in thousands for VND', () {
      expect(amountSuggestions(4500, 'VND'), [4500000, 45000000, 450000000]);
    });

    test('works for 1 to 999 and stops once the zeros are typed', () {
      expect(amountSuggestions(100, 'VND').first, 100000);
      expect(amountSuggestions(99900, 'VND').first, 99900000);
      expect(amountSuggestions(100000, 'VND'), isEmpty);
    });

    test('nothing for empty, zero or a currency with decimals', () {
      expect(amountSuggestions(null, 'VND'), isEmpty);
      expect(amountSuggestions(0, 'VND'), isEmpty);
      expect(amountSuggestions(4500, 'EUR'), isEmpty);
      expect(amountSuggestions(4500, 'USD'), isEmpty);
    });

    test('follows the currency code, in any case', () {
      expect(amountSuggestions(4500, 'idr'), isNotEmpty);
      expect(amountSuggestions(4500, 'KRW'), isNotEmpty);
    });
  });

  group('appendThousand', () {
    test('appends three zeros to the typed amount', () {
      expect(appendThousand(4500, 'VND'), 4500000);
      expect(appendThousand(4500000, 'VND'), 4500000000);
    });

    test('nothing to append to, or a currency with decimals', () {
      expect(appendThousand(null, 'VND'), isNull);
      expect(appendThousand(0, 'VND'), isNull);
      expect(appendThousand(4500, 'EUR'), isNull);
    });

    test('never goes past the 12 digits the field accepts', () {
      expect(appendThousand(999999999 * 100, 'VND'), 999999999000 * 100);
      expect(appendThousand(1000000000 * 100, 'VND'), isNull);
    });
  });
}
