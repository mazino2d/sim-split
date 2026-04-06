import 'package:fpdart/fpdart.dart';
import '../entities/settlement.dart';
import '../failures/core_failure.dart';

abstract interface class SettlementRepository {
  Stream<Either<Failure, List<Settlement>>> watchSettlementsByGroup(String groupId);
  Future<Either<Failure, Settlement>> addSettlement(Settlement settlement);
  Future<Either<Failure, Unit>> deleteSettlement(String id);
}
