import 'package:fpdart/fpdart.dart';
import '../../domain/entities/settlement.dart';
import '../../domain/failures/core_failure.dart';
import '../../domain/repositories/settlement_repository.dart';
import '../daos/settlement_dao.dart';
import '../mappers/settlement_mapper.dart';

class DriftSettlementRepository implements SettlementRepository {
  const DriftSettlementRepository({
    required SettlementDao settlementDao,
    required SettlementMapper mapper,
  })  : _settlementDao = settlementDao,
        _mapper = mapper;

  final SettlementDao _settlementDao;
  final SettlementMapper _mapper;

  @override
  Stream<Either<Failure, List<Settlement>>> watchSettlementsByGroup(
      String groupId) {
    return _settlementDao
        .watchSettlementsByGroup(groupId)
        .map((rows) => right<Failure, List<Settlement>>(
              rows.map(_mapper.toEntity).toList(),
            ))
        .handleError(
          (Object e) => left<Failure, List<Settlement>>(
            Failure.dbFailure(e.toString()),
          ),
        );
  }

  @override
  Future<Either<Failure, Settlement>> addSettlement(
      Settlement settlement) async {
    try {
      await _settlementDao.insertSettlement(_mapper.toCompanion(settlement));
      return right(settlement);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteSettlement(String id) async {
    try {
      await _settlementDao.deleteSettlementById(id);
      return right(unit);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }
}
