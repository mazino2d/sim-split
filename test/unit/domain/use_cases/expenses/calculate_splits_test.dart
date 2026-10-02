import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/expense_split.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/use_cases/expenses/calculate_splits.dart';

void main() {
  const useCase = CalculateSplits();

  Either<Failure, List<ExpenseSplit>> run(
    SplitType type,
    int total,
    List<RawSplitInput> inputs,
  ) =>
      useCase(CalculateSplitsParams(
        expenseId: 'e',
        totalAmountCents: total,
        splitType: type,
        inputs: inputs,
      ));

  List<int> amounts(Either<Failure, List<ExpenseSplit>> result) => result
      .getOrElse((f) => throw StateError('unexpected $f'))
      .map((s) => s.amountCents)
      .toList();

  Failure failureOf(Either<Failure, List<ExpenseSplit>> result) =>
      result.getLeft().toNullable()!;

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

  group('CalculateSplits - validation', () {
    test('rejects negative total', () {
      final result = run(SplitType.equal, -100, const [
        RawSplitInput(memberId: 'm1'),
      ]);
      expect(failureOf(result), isA<AmountMustBePositive>());
    });

    for (final type in SplitType.values) {
      test('rejects duplicate member ids for ${type.name}', () {
        final result = run(type, 100, const [
          RawSplitInput(memberId: 'm1', value: 50),
          RawSplitInput(memberId: 'm1', value: 50),
        ]);
        expect(failureOf(result), isA<DuplicateParticipant>());
      });
    }

    test('rejects negative percentage even if sum is 100%', () {
      final result = run(SplitType.percentage, 10000, const [
        RawSplitInput(memberId: 'm1', value: 12000),
        RawSplitInput(memberId: 'm2', value: -2000),
      ]);
      expect(failureOf(result), isA<NegativeSplitValue>());
    });

    test('rejects negative exact value even if sum matches total', () {
      final result = run(SplitType.exact, 10000, const [
        RawSplitInput(memberId: 'm1', value: 12000),
        RawSplitInput(memberId: 'm2', value: -2000),
      ]);
      expect(failureOf(result), isA<NegativeSplitValue>());
    });

    test('rejects negative shares', () {
      final result = run(SplitType.shares, 10000, const [
        RawSplitInput(memberId: 'm1', value: 2),
        RawSplitInput(memberId: 'm2', value: -1),
      ]);
      expect(failureOf(result), isA<InvalidShares>());
    });

    test('allows zero exact value', () {
      final result = run(SplitType.exact, 10000, const [
        RawSplitInput(memberId: 'm1', value: 10000),
        RawSplitInput(memberId: 'm2', value: 0),
      ]);
      expect(amounts(result), [10000, 0]);
    });
  });

  group('CalculateSplits - largest remainder', () {
    test('0% last member never receives leftover cents', () {
      final result = run(SplitType.percentage, 10, const [
        RawSplitInput(memberId: 'm1', value: 3333),
        RawSplitInput(memberId: 'm2', value: 6667),
        RawSplitInput(memberId: 'm3', value: 0),
      ]);
      // 3.333 → 3, 6.667 → 6, leftover 1 goes to largest remainder (m2)
      expect(amounts(result), [3, 7, 0]);
    });

    test('0% member in the middle gets nothing', () {
      final result = run(SplitType.percentage, 1, const [
        RawSplitInput(memberId: 'm1', value: 5000),
        RawSplitInput(memberId: 'm2', value: 0),
        RawSplitInput(memberId: 'm3', value: 5000),
      ]);
      // Tie on remainder → earliest input wins.
      expect(amounts(result), [1, 0, 0]);
    });

    test('shares remainder: 10 cents over [1, 1, 1]', () {
      final result = run(SplitType.shares, 10, const [
        RawSplitInput(memberId: 'm1', value: 1),
        RawSplitInput(memberId: 'm2', value: 1),
        RawSplitInput(memberId: 'm3', value: 1),
      ]);
      expect(amounts(result), [4, 3, 3]);
    });

    test('shares remainder goes to largest fractional part', () {
      // 100 * [1, 2, 4] / 7 = 14.28, 28.57, 57.14 → leftover 1 → m2
      final result = run(SplitType.shares, 100, const [
        RawSplitInput(memberId: 'm1', value: 1),
        RawSplitInput(memberId: 'm2', value: 2),
        RawSplitInput(memberId: 'm3', value: 4),
      ]);
      expect(amounts(result), [14, 29, 57]);
    });
  });

  group('CalculateSplits - total preserved', () {
    const totals = [1, 2, 7, 10, 99, 100, 101, 12345, 9999999];
    final cases = <SplitType, List<RawSplitInput> Function(int)>{
      SplitType.equal: (_) => const [
            RawSplitInput(memberId: 'm1'),
            RawSplitInput(memberId: 'm2'),
            RawSplitInput(memberId: 'm3'),
            RawSplitInput(memberId: 'm4'),
            RawSplitInput(memberId: 'm5'),
            RawSplitInput(memberId: 'm6'),
            RawSplitInput(memberId: 'm7'),
          ],
      SplitType.percentage: (_) => const [
            RawSplitInput(memberId: 'm1', value: 1111),
            RawSplitInput(memberId: 'm2', value: 2222),
            RawSplitInput(memberId: 'm3', value: 0),
            RawSplitInput(memberId: 'm4', value: 6667),
          ],
      SplitType.exact: (total) => [
            RawSplitInput(memberId: 'm1', value: total ~/ 3),
            RawSplitInput(memberId: 'm2', value: total - total ~/ 3),
          ],
      SplitType.shares: (_) => const [
            RawSplitInput(memberId: 'm1', value: 3),
            RawSplitInput(memberId: 'm2', value: 5),
            RawSplitInput(memberId: 'm3', value: 7),
          ],
    };

    for (final entry in cases.entries) {
      test('sum equals total for ${entry.key.name}', () {
        for (final total in totals) {
          final result = run(entry.key, total, entry.value(total));
          final split = amounts(result);
          expect(split.fold(0, (a, b) => a + b), total, reason: 'total=$total');
          expect(split.every((a) => a >= 0), isTrue, reason: 'total=$total');
        }
      });
    }
  });
}
