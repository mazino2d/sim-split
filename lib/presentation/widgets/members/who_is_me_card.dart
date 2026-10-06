import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/notifiers/member_notifier.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/widgets/common/member_avatar.dart';

/// Asks, once and inline, which member the signed-in account is, for a
/// group with several members and no "me" (AC7). Picking a member links it
/// to the account. Hidden when accounts are not available.
class WhoIsMeCard extends ConsumerStatefulWidget {
  const WhoIsMeCard({super.key, required this.groupId});

  final String groupId;

  /// SharedPreferences key remembering that the question was answered or
  /// dismissed for a group.
  static String askedKey(String groupId) => 'whoIsMeAsked.$groupId';

  @override
  ConsumerState<WhoIsMeCard> createState() => _WhoIsMeCardState();
}

class _WhoIsMeCardState extends ConsumerState<WhoIsMeCard> {
  // Null until the stored answer is loaded; the card stays hidden meanwhile.
  bool? _asked;

  @override
  void initState() {
    super.initState();
    _loadAsked();
  }

  Future<void> _loadAsked() async {
    final prefs = await SharedPreferences.getInstance();
    final asked = prefs.getBool(WhoIsMeCard.askedKey(widget.groupId)) ?? false;
    if (mounted) setState(() => _asked = asked);
  }

  Future<void> _markAsked() async {
    setState(() => _asked = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(WhoIsMeCard.askedKey(widget.groupId), true);
  }

  Future<void> _pick(Member member) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final result = await ref.read(memberProvider.notifier).updateMember(
          id: member.id,
          groupId: member.groupId,
          name: member.name,
          avatarColorValue: member.avatarColorValue,
          emoji: member.emoji,
          isMe: true,
          createdAt: member.createdAt,
        );
    result.fold(
      (f) => messenger
          .showSnackBar(SnackBar(content: Text(failureMessage(f, l10n)))),
      (_) => _markAsked(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the mutation notifier alive while a pick is saving.
    ref.watch(memberProvider);
    final members = ref.watch(memberListProvider(widget.groupId)).value ?? [];
    final show = ref.watch(authAvailableProvider) &&
        _asked == false &&
        members.length > 1 &&
        !members.any((m) => m.isMe);
    if (!show) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppTheme.gutter, 0, AppTheme.gutter, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.whoIsMeTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              l10n.whoIsMeHint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // A name another account claimed cannot be yours (AC10).
                for (final member in members.where((m) => m.linkedUid == null))
                  ActionChip(
                    avatar: MemberAvatar(member: member, size: 24),
                    label: Text(member.name),
                    onPressed: () => _pick(member),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _markAsked,
                child: Text(l10n.notNow),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
