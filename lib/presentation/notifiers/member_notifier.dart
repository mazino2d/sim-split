import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/members/add_member.dart';
import 'package:simsplit/domain/use_cases/members/remove_member.dart';
import 'package:simsplit/domain/use_cases/members/update_member.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

part 'member_notifier.g.dart';

/// Member mutations. Methods return the use case result directly; [state]
/// only reflects loading for UI (e.g. disabling Save).
@riverpod
class MemberNotifier extends _$MemberNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Runs a use case as a tracked operation (R-4 AC8).
  Future<Either<Failure, T>> _run<T>(
    TelemetryEvent event,
    Future<Either<Failure, T>> Function() action,
  ) async {
    state = const AsyncLoading();
    final result = await trackOp(ref.read(trackEventProvider), event, action);
    if (ref.mounted) {
      state = result.fold(
        (failure) => AsyncError(failure, StackTrace.current),
        (_) => const AsyncData(null),
      );
    }
    return result;
  }

  Future<Either<Failure, Member>> addMember({
    required String groupId,
    required String name,
    int avatarColorValue = 0xFF1976D2,
    String? emoji,
    bool isMe = false,
  }) {
    final useCase = ref.read(addMemberProvider);
    return _run(
        TelemetryEvent.opAddMember,
        () => useCase(AddMemberParams(
              groupId: groupId,
              name: name,
              avatarColorValue: avatarColorValue,
              emoji: emoji,
              isMe: isMe,
            )));
  }

  Future<Either<Failure, Member>> updateMember({
    required String id,
    required String groupId,
    required String name,
    required int avatarColorValue,
    String? emoji,
    required bool isMe,
    required DateTime createdAt,
  }) {
    final useCase = ref.read(updateMemberProvider);
    return _run(
        TelemetryEvent.opUpdateMember,
        () => useCase(UpdateMemberParams(
              id: id,
              groupId: groupId,
              name: name,
              avatarColorValue: avatarColorValue,
              emoji: emoji,
              isMe: isMe,
              createdAt: createdAt,
            )));
  }

  Future<Either<Failure, Unit>> removeMember(String memberId, String groupId) {
    final useCase = ref.read(removeMemberProvider);
    return _run(
        TelemetryEvent.opRemoveMember,
        () =>
            useCase(RemoveMemberParams(memberId: memberId, groupId: groupId)));
  }
}
