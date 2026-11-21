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
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/utils/tracking.dart';
import 'package:simsplit/presentation/widgets/groups/archive_group.dart';

enum _MenuAction { activity, edit, archive, reopen, leave }

/// App bar actions for a group: Share group (R-3 AC9) and a More menu that
/// keeps the less frequent actions out of the bar — Activity (AC25), Edit
/// group (which holds the settlement mode and Reset invite link), Archive
/// and Leave group (when other accounts are in it, AC14). Without accounts,
/// the menu offers Edit and Archive.
class GroupAppBarActions extends ConsumerWidget {
  const GroupAppBarActions({super.key, required this.groupId});

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
    String groupId,
    Group? group,
    _MenuAction action,
  ) async {
    switch (action) {
      case _MenuAction.activity:
        await context.push('/groups/$groupId/activity');
        return;
      case _MenuAction.edit:
        await context.push('/groups/$groupId/edit');
        return;
      case _MenuAction.archive || _MenuAction.reopen:
        final local = ref.read(liveGroupProvider(groupId)).value;
        if (local == null) return;
        if (action == _MenuAction.archive) {
          await confirmAndArchiveGroup(context, ref, local);
        } else {
          await reopenGroup(context, ref, local);
        }
        return;
      case _MenuAction.leave:
        await _confirmAndLeave(context, ref, group!);
    }
  }

  Future<void> _confirmAndLeave(
    BuildContext context,
    WidgetRef ref,
    Group group,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final (title, message, confirm) = (
      l10n.leaveGroupConfirmTitle,
      l10n.leaveGroupConfirmMessage,
      l10n.leaveGroupConfirm,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: dCtx.tracked(TelemetryEvent.tapDialogCancel,
                () => Navigator.pop(dCtx, false)),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dCtx).colorScheme.error,
              foregroundColor: Theme.of(dCtx).colorScheme.onError,
              minimumSize: const Size(64, 44),
            ),
            onPressed: dCtx.tracked(TelemetryEvent.tapDialogConfirm,
                () => Navigator.pop(dCtx, true)),
            child: Text(confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await ref.read(inviteProvider.notifier).leaveGroup(group.id);
    result.fold(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(failure, l10n))),
      ),
      (_) => router.go('/'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final synced = ref.watch(authAvailableProvider);
    final group = synced ? ref.watch(liveGroupProvider(groupId)).value : null;
    final uid = synced ? ref.watch(currentUserProvider).value?.uid : null;
    // Keeps the notifier alive while an action runs.
    final busy = synced && ref.watch(inviteProvider).isLoading;

    final othersIn = group != null && group.memberUids.any((u) => u != uid);
    // Archiving works offline too, so it reads the local group (#117).
    final local = ref.watch(liveGroupProvider(groupId)).value;
    final archived = local?.isArchived ?? false;
    final canArchive = local != null && canArchiveGroup(ref, local);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (group != null)
          IconButton(
            icon: const Icon(Icons.person_add_alt_outlined),
            tooltip: l10n.shareGroup,
            onPressed: context.tracked(TelemetryEvent.tapShareGroup,
                busy ? null : () => _share(context, ref, group)),
          ),
        PopupMenuButton<_MenuAction>(
          tooltip: l10n.groupMenu,
          enabled: !busy,
          onSelected: (action) {
            context.track(switch (action) {
              _MenuAction.activity => TelemetryEvent.tapMenuActivity,
              _MenuAction.edit => TelemetryEvent.tapMenuEdit,
              _MenuAction.archive => TelemetryEvent.tapArchiveGroup,
              _MenuAction.reopen => TelemetryEvent.tapReopenGroup,
              _MenuAction.leave => TelemetryEvent.tapMenuLeave,
            });
            _onMenu(context, ref, groupId, group, action);
          },
          itemBuilder: (_) => [
            if (group != null)
              PopupMenuItem(
                value: _MenuAction.activity,
                child: Text(l10n.activity),
              ),
            if (!archived)
              PopupMenuItem(
                value: _MenuAction.edit,
                child: Text(l10n.editGroup),
              ),
            if (canArchive)
              PopupMenuItem(
                value: archived ? _MenuAction.reopen : _MenuAction.archive,
                child: Text(archived ? l10n.reopenGroup : l10n.archiveGroup),
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
