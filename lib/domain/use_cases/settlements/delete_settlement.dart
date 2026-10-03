import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/settlement_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class DeleteSettlementParams {
  const DeleteSettlementParams({required this.id});
  final String id;
}

/// Removes a recorded settlement, e.g. one entered by mistake. The debt it
/// paid off reappears because balances are recomputed from history.
class DeleteSettlement implements AsyncUseCase<Unit, DeleteSettlementParams> {
  const DeleteSettlement({required SettlementRepository settlementRepository})
      : _settlementRepository = settlementRepository;

  final SettlementRepository _settlementRepository;

  @override
  Future<Either<Failure, Unit>> call(DeleteSettlementParams params) =>
      _settlementRepository.deleteSettlement(params.id);
}
