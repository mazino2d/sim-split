import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/use_cases/members/remove_member.dart';
import 'package:simsplit/domain/use_cases/members/update_member.dart';

part 'member_notifier.g.dart';

@riverpod
class MemberNotifier extends _$MemberNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> updateMember({
    required String id,
    required String groupId,
    required String name,
    required int avatarColorValue,
    String? emoji,
    required bool isMe,
    required DateTime createdAt,
  }) async {
    state = const AsyncLoading();
    final useCase = ref.read(updateMemberProvider);
    final result = await useCase(UpdateMemberParams(
      id: id,
      groupId: groupId,
      name: name,
      avatarColorValue: avatarColorValue,
      emoji: emoji,
      isMe: isMe,
      createdAt: createdAt,
    ));

    return result.fold(
      (failure) {
        state = AsyncError(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncData(null);
        return true;
      },
    );
  }

  Future<bool> removeMember(String memberId, String groupId) async {
    state = const AsyncLoading();
    final useCase = ref.read(removeMemberProvider);
    final result =
        await useCase(RemoveMemberParams(memberId: memberId, groupId: groupId));

    return result.fold(
      (failure) {
        state = AsyncError(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncData(null);
        return true;
      },
    );
  }
}
