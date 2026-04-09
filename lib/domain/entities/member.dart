import 'package:freezed_annotation/freezed_annotation.dart';

part 'member.freezed.dart';

@freezed
class Member with _$Member {
  const factory Member({
    required String id,
    required String groupId,
    required String name,
    required int avatarColorValue,
    String? emoji,
    @Default(false) bool isMe,
    required DateTime createdAt,
  }) = _Member;
}
