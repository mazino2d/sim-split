import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:simsplit/domain/entities/member.dart';

part 'group.freezed.dart';

@freezed
sealed class Group with _$Group {
  const factory Group({
    required String id,
    required String name,
    String? emoji,
    required int colorValue,
    required String currencyCode,
    @Default(false) bool isArchived,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default([]) List<Member> members,
  }) = _Group;
}
