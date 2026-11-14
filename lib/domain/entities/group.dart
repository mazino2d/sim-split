import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:simsplit/domain/entities/member.dart';

part 'group.freezed.dart';

/// How a group's suggested settlements are worked out (#116).
enum SettlementMode {
  /// Everyone settles with one collector (the owner's member by default).
  hub,

  /// The fewest transfers between any members.
  simplified,
}

@freezed
sealed class Group with _$Group {
  const factory Group({
    required String id,
    required String name,
    String? emoji,
    required int colorValue,
    required String currencyCode,
    @Default(false) bool isArchived,

    /// Groups created before R-7 have no mode stored and read as
    /// [SettlementMode.simplified]; new groups start with [SettlementMode.hub].
    @Default(SettlementMode.simplified) SettlementMode settlementMode,

    /// The member everyone settles with in [SettlementMode.hub]; null means
    /// the owner's member.
    String? settlementHubMemberId,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default([]) List<Member> members,

    /// Sharing state from the cloud (R-3): the owning account, the accounts
    /// in the group and the current invite token. Empty until the group has
    /// synced.
    String? ownerUid,
    @Default([]) List<String> memberUids,
    String? inviteToken,
  }) = _Group;
}
