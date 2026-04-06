import 'package:fpdart/fpdart.dart';
import '../../failures/core_failure.dart';
import '../../repositories/group_repository.dart';
import '../use_case.dart';

class DeleteGroupParams {
  const DeleteGroupParams({required this.id});
  final String id;
}

class DeleteGroup implements AsyncUseCase<Unit, DeleteGroupParams> {
  const DeleteGroup({required GroupRepository groupRepository})
      : _groupRepository = groupRepository;

  final GroupRepository _groupRepository;

  @override
  Future<Either<Failure, Unit>> call(DeleteGroupParams params) =>
      _groupRepository.deleteGroup(params.id);
}
