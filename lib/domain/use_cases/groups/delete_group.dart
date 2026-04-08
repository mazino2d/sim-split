import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

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
