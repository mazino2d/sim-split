import 'package:fpdart/fpdart.dart' hide Group;
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class ListGroups implements StreamUseCase<List<Group>, NoParams> {
  const ListGroups({required GroupRepository groupRepository})
      : _groupRepository = groupRepository;

  final GroupRepository _groupRepository;

  @override
  Stream<Either<Failure, List<Group>>> call(NoParams params) =>
      _groupRepository.watchGroups();
}
