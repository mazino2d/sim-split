import 'package:fpdart/fpdart.dart' hide Group;
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class UpdateGroupParams {
  const UpdateGroupParams({
    required this.id,
    required this.name,
    required this.currencyCode,
    this.emoji,
    this.colorValue,
    this.isArchived,
  });

  final String id;
  final String name;
  final String currencyCode;
  final String? emoji;
  final int? colorValue;
  final bool? isArchived;
}

class UpdateGroup implements AsyncUseCase<Group, UpdateGroupParams> {
  const UpdateGroup({required GroupRepository groupRepository})
      : _groupRepository = groupRepository;

  final GroupRepository _groupRepository;

  @override
  Future<Either<Failure, Group>> call(UpdateGroupParams params) async {
    if (params.name.trim().isEmpty) {
      return left(const GroupFailure.nameTooShort());
    }
    if (params.name.trim().length > 100) {
      return left(const GroupFailure.nameTooLong());
    }

    final existingResult = await _groupRepository.getGroup(params.id);
    return existingResult.fold<Future<Either<Failure, Group>>>(
      (failure) async => left(failure),
      (existing) {
        final updated = existing.copyWith(
          name: params.name.trim(),
          currencyCode: params.currencyCode,
          emoji: params.emoji ?? existing.emoji,
          colorValue: params.colorValue ?? existing.colorValue,
          isArchived: params.isArchived ?? existing.isArchived,
          updatedAt: DateTime.now(),
        );
        return _groupRepository.updateGroup(updated);
      },
    );
  }
}
