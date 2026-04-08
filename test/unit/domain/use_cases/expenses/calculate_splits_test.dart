import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/use_cases/expenses/calculate_splits.dart';

void main() {
  const useCase = CalculateSplits();

  group('CalculateSplits - equal', () {
    test('splits evenly with no remainder', () {
      final result = useCase(const CalculateSplitsParams(
        expenseId: 'e1',
        totalAmountCents: 30000,
        splitType: SplitType.equal,
        inputs: [
          RawSplitInput(memberId: 'm1'),
          RawSplitInput(memberId: 'm2'),
          RawSplitInput(memberId: 'm3'),
        ],
      ));
      final splits = result.getOrElse((_) => throw Exception());
      expect(splits.map((s) => s.amountCents), [10000, 10000, 10000]);
      expect(splits.fold(0, (s, e) => s + e.amountCents), 30000);
    });

    test('distributes remainder cents to first members', () {
      final result = useCase(const CalculateSplitsParams(
        expenseId: 'e2',
        totalAmountCents: 10,
        splitType: SplitType.equal,
        inputs: [
          RawSplitInput(memberId: 'm1'),
          RawSplitInput(memberId: 'm2'),
          RawSplitInput(memberId: 'm3'),
        ],
      ));
      final splits = result.getOrElse((_) => throw Exception());
      // 10 / 3 = 3 remainder 1 → [4, 3, 3]
      expect(splits.map((s) => s.amountCents), [4, 3, 3]);
      expect(splits.fold(0, (s, e) => s + e.amountCents), 10);
    });

    test('single member gets full amount', () {
      final result = useCase(const CalculateSplitsParams(
        expenseId: 'e3',
        totalAmountCents: 50000,
        splitType: SplitType.equal,
        inputs: [RawSplitInput(memberId: 'm1')],
      ));
      final splits = result.getOrElse((_) => throw Exception());
      expect(splits.single.amountCents, 50000);
    });
  });

  group('CalculateSplits - percentage', () {
    test('valid 50/50 split', () {
      final result = useCase(const CalculateSplitsParams(
        expenseId: 'e4',
        totalAmountCents: 20000,
        splitType: SplitType.percentage,
        inputs: [
          RawSplitInput(memberId: 'm1', value: 5000), // 50%
          RawSplitInput(memberId: 'm2', value: 5000), // 50%
        ],
      ));
      final splits = result.getOrElse((_) => throw Exception());
      expect(splits.map((s) => s.amountCents), [10000, 10000]);
    });

    test('fails when percentages do not sum to 100', () {
      final result = useCase(const CalculateSplitsParams(
        expenseId: 'e5',
        totalAmountCents: 10000,
        splitType: SplitType.percentage,
        inputs: [
          RawSplitInput(memberId: 'm1', value: 3000),
          RawSplitInput(memberId: 'm2', value: 3000), // total 60%
        ],
      ));
      expect(result.isLeft(), isTrue);
    });

    test('last member absorbs rounding', () {
      final result = useCase(const CalculateSplitsParams(
        expenseId: 'e6',
        totalAmountCents: 10,
        splitType: SplitType.percentage,
        inputs: [
          RawSplitInput(memberId: 'm1', value: 3333), // 33.33%
          RawSplitInput(memberId: 'm2', value: 3333), // 33.33%
          RawSplitInput(memberId: 'm3', value: 3334), // 33.34% → totals 10000
        ],
      ));
      final splits = result.getOrElse((_) => throw Exception());
      expect(splits.fold(0, (s, e) => s + e.amountCents), 10);
    });
  });

  group('CalculateSplits - exact', () {
    test('valid exact split', () {
      final result = useCase(const CalculateSplitsParams(
        expenseId: 'e7',
        totalAmountCents: 15000,
        splitType: SplitType.exact,
        inputs: [
          RawSplitInput(memberId: 'm1', value: 5000),
          RawSplitInput(memberId: 'm2', value: 10000),
        ],
      ));
      final splits = result.getOrElse((_) => throw Exception());
      expect(splits.map((s) => s.amountCents), [5000, 10000]);
    });

    test('fails when exact amounts do not sum to total', () {
      final result = useCase(const CalculateSplitsParams(
        expenseId: 'e8',
        totalAmountCents: 15000,
        splitType: SplitType.exact,
        inputs: [
          RawSplitInput(memberId: 'm1', value: 5000),
          RawSplitInput(memberId: 'm2', value: 9000), // 14000 ≠ 15000
        ],
      ));
      expect(result.isLeft(), isTrue);
    });
  });

  group('CalculateSplits - shares', () {
    test('2:1 ratio', () {
      final result = useCase(const CalculateSplitsParams(
        expenseId: 'e9',
        totalAmountCents: 30000,
        splitType: SplitType.shares,
        inputs: [
          RawSplitInput(memberId: 'm1', value: 2),
          RawSplitInput(memberId: 'm2', value: 1),
        ],
      ));
      final splits = result.getOrElse((_) => throw Exception());
      expect(splits[0].amountCents, 20000);
      expect(splits[1].amountCents, 10000);
      expect(splits.fold(0, (s, e) => s + e.amountCents), 30000);
    });

    test('fails when any share is zero', () {
      final result = useCase(const CalculateSplitsParams(
        expenseId: 'e10',
        totalAmountCents: 10000,
        splitType: SplitType.shares,
        inputs: [
          RawSplitInput(memberId: 'm1', value: 1),
          RawSplitInput(memberId: 'm2', value: 0),
        ],
      ));
      expect(result.isLeft(), isTrue);
    });
  });

  group('CalculateSplits - edge cases', () {
    test('fails with no participants', () {
      final result = useCase(const CalculateSplitsParams(
        expenseId: 'e11',
        totalAmountCents: 10000,
        splitType: SplitType.equal,
        inputs: [],
      ));
      expect(result.isLeft(), isTrue);
    });

    test('fails with zero amount', () {
      final result = useCase(const CalculateSplitsParams(
        expenseId: 'e12',
        totalAmountCents: 0,
        splitType: SplitType.equal,
        inputs: [RawSplitInput(memberId: 'm1')],
      ));
      expect(result.isLeft(), isTrue);
    });
  });
}
