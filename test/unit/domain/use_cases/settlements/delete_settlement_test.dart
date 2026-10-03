import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/settlements/delete_settlement.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockSettlementRepository settlements;
  late DeleteSettlement useCase;

  setUp(() {
    settlements = MockSettlementRepository();
    useCase = DeleteSettlement(settlementRepository: settlements);
  });

  test('deletes the settlement with the given id', () async {
    when(() => settlements.deleteSettlement('s1'))
        .thenAnswer((_) async => right(unit));

    final result = await useCase(const DeleteSettlementParams(id: 's1'));

    expect(result, right<Failure, Unit>(unit));
    verify(() => settlements.deleteSettlement('s1')).called(1);
  });

  test('passes a repository failure through unchanged', () async {
    const failure = Failure.dbFailure('disk full');
    when(() => settlements.deleteSettlement('s1'))
        .thenAnswer((_) async => left(failure));

    final result = await useCase(const DeleteSettlementParams(id: 's1'));

    expect(leftOf(result), failure);
  });
}
