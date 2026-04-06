import 'package:fpdart/fpdart.dart';
import '../../entities/settlement.dart';
import '../../failures/core_failure.dart';
import '../../repositories/settlement_repository.dart';
import '../use_case.dart';

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
