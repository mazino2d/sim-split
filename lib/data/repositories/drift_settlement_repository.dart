import 'package:drift/drift.dart' show Value;
import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/settlement_repository.dart';
import 'package:simsplit/data/daos/settlement_dao.dart';
import 'package:simsplit/data/mappers/settlement_mapper.dart';
import 'package:simsplit/data/sync/sync_codec.dart';
import 'package:simsplit/data/sync/sync_recorder.dart';
import 'package:simsplit/data/utils/stream_failure_transformer.dart';

class DriftSettlementRepository implements SettlementRepository {
  const DriftSettlementRepository({
    required SettlementDao settlementDao,
    required SettlementMapper mapper,
    required SyncRecorder recorder,
    SyncCodec codec = const SyncCodec(),
  })  : _settlementDao = settlementDao,
        _mapper = mapper,
        _recorder = recorder,
        _codec = codec;

  final SettlementDao _settlementDao;
  final SettlementMapper _mapper;
  final SyncRecorder _recorder;
  final SyncCodec _codec;

  @override
  Stream<Either<Failure, List<Settlement>>> watchSettlementsByGroup(
      String groupId) {
    return _settlementDao
        .watchSettlementsByGroup(groupId)
        .map((rows) => right<Failure, List<Settlement>>(
              rows.map(_mapper.toEntity).toList(),
            ))
        .mapErrorsToDbFailure();
  }

  @override
  Future<Either<Failure, Settlement>> addSettlement(
      Settlement settlement) async {
    try {
      await _settlementDao.transaction(() async {
        final uid = _recorder.uid;
        await _settlementDao
            .insertSettlement(_mapper.toCompanion(settlement).copyWith(
                  createdBy: Value(uid),
                  updatedBy: Value(uid),
                ));
        await _recorder.record(
          groupId: settlement.groupId,
          entity: SyncEntity.settlement,
          entityId: settlement.id,
          action: SyncAction.create,
          after: _codec.settlement(
              (await _settlementDao.getSettlementById(settlement.id))!),
        );
      });
      return right(settlement);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteSettlement(String id) async {
    try {
      await _settlementDao.transaction(() async {
        final before = await _settlementDao.getSettlementById(id);
        if (before == null || before.deleted) return;
        await _settlementDao.softDeleteSettlement(id,
            updatedBy: _recorder.uid ?? before.updatedBy);
        await _recorder.record(
          groupId: before.groupId,
          entity: SyncEntity.settlement,
          entityId: id,
          action: SyncAction.delete,
          before: _codec.settlement(before),
          after:
              _codec.settlement((await _settlementDao.getSettlementById(id))!),
        );
      });
      return right(unit);
    } catch (e) {
      return left(Failure.dbFailure(e.toString()));
    }
  }
}
