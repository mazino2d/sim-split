import 'package:fpdart/fpdart.dart' hide Group;
import '../../entities/group.dart';
import '../../failures/core_failure.dart';
import '../../repositories/group_repository.dart';
import '../use_case.dart';

class GetGroupParams {
  const GetGroupParams({required this.id});
  final String id;
}

class GetGroup implements AsyncUseCase<Group, GetGroupParams> {
  const GetGroup({required GroupRepository groupRepository})
      : _groupRepository = groupRepository;

  final GroupRepository _groupRepository;

  @override
  Future<Either<Failure, Group>> call(GetGroupParams params) =>
      _groupRepository.getGroup(params.id);
}
