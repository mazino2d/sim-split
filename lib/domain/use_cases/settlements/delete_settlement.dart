import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/settlement_repository.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';
import 'package:simsplit/domain/use_cases/groups/group_guard.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class DeleteSettlementParams {
  const DeleteSettlementParams({required this.id, required this.groupId});
  final String id;
  final String groupId;
}

/// Removes a recorded settlement, e.g. one entered by mistake. The debt it
/// paid off reappears because balances are recomputed from history.
class DeleteSettlement implements AsyncUseCase<Unit, DeleteSettlementParams> {
  const DeleteSettlement({
    required SettlementRepository settlementRepository,
    required GroupRepository groupRepository,
  })  : _settlementRepository = settlementRepository,
        _groupRepository = groupRepository;

  final SettlementRepository _settlementRepository;
  final GroupRepository _groupRepository;

  @override
  Future<Either<Failure, Unit>> call(DeleteSettlementParams params) async {
    if (await ensureGroupWritable(_groupRepository, params.groupId)
        case Left(value: final failure)) {
      return left(failure);
    }
    return _settlementRepository.deleteSettlement(params.id);
  }
}
