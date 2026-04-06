import 'package:fpdart/fpdart.dart' hide Group;
import '../../entities/group.dart';
import '../../failures/core_failure.dart';
import '../../failures/group_failure.dart';
import '../../repositories/group_repository.dart';
import '../../value_objects/unique_id.dart';
import '../use_case.dart';

class CreateGroupParams {
  const CreateGroupParams({
    required this.name,
    required this.currencyCode,
    this.emoji,
    this.colorValue = 0xFF6200EE,
  });

  final String name;
  final String currencyCode;
  final String? emoji;
  final int colorValue;
}

class CreateGroup implements AsyncUseCase<Group, CreateGroupParams> {
  const CreateGroup({required GroupRepository groupRepository})
      : _groupRepository = groupRepository;

  final GroupRepository _groupRepository;

  @override
  Future<Either<Failure, Group>> call(CreateGroupParams params) {
    if (params.name.trim().isEmpty) {
      return Future.value(left(const GroupFailure.nameTooShort()));
    }
    if (params.name.trim().length > 100) {
      return Future.value(left(const GroupFailure.nameTooLong()));
    }

    final now = DateTime.now();
    final group = Group(
      id: UniqueId.generate().value,
      name: params.name.trim(),
      emoji: params.emoji,
      colorValue: params.colorValue,
      currencyCode: params.currencyCode,
      createdAt: now,
      updatedAt: now,
    );

    return _groupRepository.createGroup(group);
  }
}
