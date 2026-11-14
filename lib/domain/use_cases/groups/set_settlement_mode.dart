import 'package:fpdart/fpdart.dart' hide Group;
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/repositories/group_repository.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class SetSettlementModeParams {
  const SetSettlementModeParams({
    required this.groupId,
    required this.mode,
    this.hubMemberId,
  });

  final String groupId;
  final SettlementMode mode;

  /// The collector in [SettlementMode.hub]; null for the owner's member.
  /// Ignored, and cleared, in [SettlementMode.simplified].
  final String? hubMemberId;
}

/// Changes how a group's settlements are suggested (#116). Shared with every
/// member and recorded in the history like any group change.
class SetSettlementMode
    implements AsyncUseCase<Group, SetSettlementModeParams> {
  const SetSettlementMode({
    required GroupRepository groupRepository,
    required MemberRepository memberRepository,
  })  : _groupRepository = groupRepository,
        _memberRepository = memberRepository;

  final GroupRepository _groupRepository;
  final MemberRepository _memberRepository;

  @override
  Future<Either<Failure, Group>> call(SetSettlementModeParams params) async {
    final existing = await _groupRepository.getGroup(params.groupId);
    if (existing case Left(value: final failure)) return left(failure);
    final group = existing.toNullable()!;
    if (group.isArchived) return left(const GroupFailure.archived());

    final hubMemberId =
        params.mode == SettlementMode.hub ? params.hubMemberId : null;
    if (hubMemberId != null) {
      final members =
          await _memberRepository.watchMembersByGroup(params.groupId).first;
      if (members case Left(value: final failure)) return left(failure);
      if (!members.toNullable()!.any((m) => m.id == hubMemberId)) {
        return left(const GroupFailure.collectorNotInGroup());
      }
    }
    return _groupRepository.updateGroup(group.copyWith(
      settlementMode: params.mode,
      settlementHubMemberId: hubMemberId,
      updatedAt: DateTime.now(),
    ));
  }
}
