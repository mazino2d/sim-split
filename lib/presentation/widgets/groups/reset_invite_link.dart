import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/notifiers/invite_notifier.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/utils/tracking.dart';
import 'package:simsplit/presentation/widgets/common/section_label.dart';

/// The "Invite link" section of Edit group with Reset invite link (R-3
/// AC13): only the owner of a synced group that already has a link sees it.
/// The old link stops working.
class ResetInviteLinkSection extends ConsumerWidget {
  const ResetInviteLinkSection({super.key, required this.groupId});

  final String groupId;

  Future<void> _confirmAndReset(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.resetInviteLinkConfirmTitle),
        content: Text(l10n.resetInviteLinkConfirmMessage),
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
            child: Text(l10n.resetInviteLinkConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result =
        await ref.read(inviteProvider.notifier).resetInviteLink(groupId);
    messenger.showSnackBar(SnackBar(
      content: Text(result.fold(
        (failure) => failureMessage(failure, l10n),
        (_) => l10n.inviteLinkResetDone,
      )),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    if (!ref.watch(authAvailableProvider)) return const SizedBox.shrink();
    final group = ref.watch(liveGroupProvider(groupId)).value;
    final uid = ref.watch(currentUserProvider).value?.uid;
    // Keeps the notifier alive while the reset runs.
    final busy = ref.watch(inviteProvider).isLoading;
    final canReset = group != null &&
        !group.isArchived &&
        uid != null &&
        group.ownerUid == uid &&
        group.inviteToken != null;
    if (!canReset) return const SizedBox.shrink();
    final error = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(l10n.inviteLinkSection),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.link_off_rounded, color: error),
            title: Text(l10n.resetInviteLink, style: TextStyle(color: error)),
            subtitle: Text(l10n.resetInviteLinkHint),
            onTap: context.tracked(TelemetryEvent.tapResetInviteLink,
                busy ? null : () => _confirmAndReset(context, ref)),
          ),
        ),
      ],
    );
  }
}
