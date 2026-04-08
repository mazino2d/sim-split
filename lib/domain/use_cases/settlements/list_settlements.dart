import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/settlement_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class ListSettlementsParams {
  const ListSettlementsParams({required this.groupId});
  final String groupId;
}

class ListSettlements
    implements StreamUseCase<List<Settlement>, ListSettlementsParams> {
  const ListSettlements({required SettlementRepository settlementRepository})
      : _settlementRepository = settlementRepository;

  final SettlementRepository _settlementRepository;

  @override
  Stream<Either<Failure, List<Settlement>>> call(
          ListSettlementsParams params) =>
      _settlementRepository.watchSettlementsByGroup(params.groupId);
}
