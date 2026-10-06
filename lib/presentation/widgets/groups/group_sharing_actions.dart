import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/presentation/notifiers/invite_notifier.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';

enum _MenuAction { resetLink, leave }

/// App bar actions for a shared group (R-3 AC9, AC13, AC14): Share group,
/// and a menu with Reset invite link (owner only) and Leave group (when
/// other accounts are in it). Nothing without accounts.
class GroupSharingActions extends ConsumerWidget {
  const GroupSharingActions({super.key, required this.groupId});

  final String groupId;

  Future<void> _share(BuildContext context, WidgetRef ref, Group group) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(inviteProvider.notifier).inviteLink(group.id);
    await result.fold(
      (failure) async => messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(failure, l10n))),
      ),
      (link) async {
        if (kIsWeb) {
          // Browsers rarely offer a share sheet: copy the link instead, and
          // show it when the browser does not allow copying.
          var copied = true;
          try {
            // A browser may hold the request on a permission prompt.
            await Clipboard.setData(ClipboardData(text: link.toString()))
                .timeout(const Duration(seconds: 3));
          } catch (_) {
            copied = false;
          }
          messenger.showSnackBar(SnackBar(
            content: Text(copied ? l10n.inviteLinkCopied : link.toString()),
          ));
          return;
        }
        await SharePlus.instance.share(ShareParams(
          text: l10n.shareGroupMessage(group.name, link.toString()),
          subject: group.name,
        ));
      },
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    Group group,
    _MenuAction action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final (title, message, confirm) = switch (action) {
      _MenuAction.resetLink => (
          l10n.resetInviteLinkConfirmTitle,
          l10n.resetInviteLinkConfirmMessage,
          l10n.resetInviteLinkConfirm,
        ),
      _MenuAction.leave => (
          l10n.leaveGroupConfirmTitle,
          l10n.leaveGroupConfirmMessage,
          l10n.leaveGroupConfirm,
        ),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dCtx).colorScheme.error,
              foregroundColor: Theme.of(dCtx).colorScheme.onError,
              minimumSize: const Size(64, 44),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final notifier = ref.read(inviteProvider.notifier);
    switch (action) {
      case _MenuAction.resetLink:
        final result = await notifier.resetInviteLink(group.id);
        messenger.showSnackBar(SnackBar(
          content: Text(result.fold(
            (failure) => failureMessage(failure, l10n),
            (_) => l10n.inviteLinkResetDone,
          )),
        ));
      case _MenuAction.leave:
        final result = await notifier.leaveGroup(group.id);
        result.fold(
          (failure) => messenger.showSnackBar(
            SnackBar(content: Text(failureMessage(failure, l10n))),
          ),
          (_) => router.go('/'),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(authAvailableProvider)) return const SizedBox.shrink();
    final group = ref.watch(liveGroupProvider(groupId)).value;
    final uid = ref.watch(currentUserProvider).value?.uid;
    // Keeps the notifier alive while an action runs.
    final busy = ref.watch(inviteProvider).isLoading;
    if (group == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final canReset =
        uid != null && group.ownerUid == uid && group.inviteToken != null;
    final othersIn = group.memberUids.any((u) => u != uid);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.person_add_alt_outlined),
          tooltip: l10n.shareGroup,
          onPressed: busy ? null : () => _share(context, ref, group),
        ),
        if (canReset || othersIn)
          PopupMenuButton<_MenuAction>(
            tooltip: l10n.groupMenu,
            enabled: !busy,
            onSelected: (action) => _onMenu(context, ref, group, action),
            itemBuilder: (_) => [
              if (canReset)
                PopupMenuItem(
                  value: _MenuAction.resetLink,
                  child: Text(l10n.resetInviteLink),
                ),
              if (othersIn)
                PopupMenuItem(
                  value: _MenuAction.leave,
                  child: Text(l10n.leaveGroup),
                ),
            ],
          ),
      ],
    );
  }
}
