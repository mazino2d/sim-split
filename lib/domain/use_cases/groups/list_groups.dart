import 'package:fpdart/fpdart.dart' hide Group;
import '../../entities/group.dart';
import '../../failures/core_failure.dart';
import '../../repositories/group_repository.dart';
import '../use_case.dart';

class ListGroups implements StreamUseCase<List<Group>, NoParams> {
  const ListGroups({required GroupRepository groupRepository})
      : _groupRepository = groupRepository;

  final GroupRepository _groupRepository;

  @override
  Stream<Either<Failure, List<Group>>> call(NoParams params) =>
      _groupRepository.watchGroups();
}
