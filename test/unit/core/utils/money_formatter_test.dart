import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/utils/money_formatter.dart';

void main() {
  group('parseMoneyToCents — decimal currencies', () {
    test('parses dot decimal', () {
      expect(parseMoneyToCents('12.50', 'USD'), 1250);
      expect(parseMoneyToCents('12.5', 'USD'), 1250);
      expect(parseMoneyToCents('0.01', 'EUR'), 1);
    });

    test('parses comma decimal', () {
      expect(parseMoneyToCents('12,50', 'EUR'), 1250);
      expect(parseMoneyToCents('12,5', 'SGD'), 1250);
    });

    test('parses integers and trailing separator', () {
      expect(parseMoneyToCents('12', 'USD'), 1200);
      expect(parseMoneyToCents('12.', 'USD'), 1200);
      expect(parseMoneyToCents('.5', 'USD'), 50);
    });

    test('parses thousands grouping', () {
      expect(parseMoneyToCents('1,234.56', 'USD'), 123456);
      expect(parseMoneyToCents('1.234,56', 'EUR'), 123456);
      expect(parseMoneyToCents('1,250', 'USD'), 125000);
      expect(parseMoneyToCents('1,234,567', 'THB'), 123456700);
      expect(parseMoneyToCents('1 234.5', 'USD'), 123450);
    });

    test('rejects malformed input', () {
      expect(parseMoneyToCents('', 'USD'), isNull);
      expect(parseMoneyToCents('   ', 'USD'), isNull);
      expect(parseMoneyToCents('abc', 'USD'), isNull);
      expect(parseMoneyToCents('-5', 'USD'), isNull);
      expect(parseMoneyToCents('12.345.6', 'USD'), isNull);
      expect(parseMoneyToCents('1,23.45', 'USD'), isNull);
      expect(parseMoneyToCents('12.5x', 'USD'), isNull);
      expect(parseMoneyToCents('12.345', 'USD'), 1234500);
    });
  });

  group('parseMoneyToCents — zero-decimal currencies', () {
    test('parses integer units', () {
      expect(parseMoneyToCents('100000', 'VND'), 10000000);
      expect(parseMoneyToCents('0', 'VND'), 0);
    });

    test('accepts thousands separators', () {
      expect(parseMoneyToCents('100.000', 'VND'), 10000000);
      expect(parseMoneyToCents('100,000', 'VND'), 10000000);
      expect(parseMoneyToCents('1.000.000', 'VND'), 100000000);
      expect(parseMoneyToCents('1 000 000', 'JPY'), 100000000);
    });

    test('rejects decimals and malformed grouping', () {
      expect(parseMoneyToCents('12.5', 'VND'), isNull);
      expect(parseMoneyToCents('1.00.000', 'VND'), isNull);
      expect(parseMoneyToCents('1.000,000', 'VND'), isNull);
      expect(parseMoneyToCents('-1000', 'VND'), isNull);
      expect(parseMoneyToCents('', 'VND'), isNull);
    });
  });

  group('formatCentsForInput', () {
    test('decimal currencies keep exact cents', () {
      expect(formatCentsForInput(1250, 'USD'), '12.50');
      expect(formatCentsForInput(1205, 'USD'), '12.05');
      expect(formatCentsForInput(1200, 'USD'), '12');
      expect(formatCentsForInput(1, 'EUR'), '0.01');
      expect(formatCentsForInput(0, 'USD'), '0');
      expect(formatCentsForInput(123456789, 'USD'), '1234567.89');
    });

    test('zero-decimal currencies use whole units with grouping', () {
      expect(formatCentsForInput(10000000, 'VND'), '100.000');
      expect(formatCentsForInput(100, 'VND'), '1');
      expect(formatCentsForInput(0, 'VND'), '0');
      // Residual sub-unit cents are rounded to the nearest unit.
      expect(formatCentsForInput(3333333, 'VND'), '33.333');
      expect(formatCentsForInput(3333350, 'VND'), '33.334');
    });

    test('round-trips through parseMoneyToCents', () {
      for (final cents in [1, 99, 100, 1250, 99999, 123456789]) {
        expect(
          parseMoneyToCents(formatCentsForInput(cents, 'USD'), 'USD'),
          cents,
        );
      }
      for (final cents in [0, 100, 10000000, 123456700]) {
        expect(
          parseMoneyToCents(formatCentsForInput(cents, 'VND'), 'VND'),
          cents,
        );
      }
    });
  });
}
