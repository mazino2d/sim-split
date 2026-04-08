import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/settlement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';

abstract interface class SettlementRepository {
  Stream<Either<Failure, List<Settlement>>> watchSettlementsByGroup(
      String groupId);
  Future<Either<Failure, Settlement>> addSettlement(Settlement settlement);
  Future<Either<Failure, Unit>> deleteSettlement(String id);
}
