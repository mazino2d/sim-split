import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/notifiers/group_notifier.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

/// Whether this account may archive or reopen [group]: its owner, or anyone
/// on this device while the group hasn't synced and has no owner yet (#117).
bool canArchiveGroup(WidgetRef ref, Group group) {
  final owner = group.ownerUid;
  if (owner == null) return true;
  final synced = ref.watch(authAvailableProvider);
  return synced && ref.watch(currentUserProvider).value?.uid == owner;
}

/// Asks, then archives [group]. The dialog says what happens and warns when
/// someone still owes money, but archiving is still allowed.
Future<void> confirmAndArchiveGroup(
  BuildContext context,
  WidgetRef ref,
  Group group,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  int owing;
  try {
    final summary = await ref
        .read(debtSummaryProvider(group.id, group.currencyCode).future);
    owing = summary.balances.where((b) => b.netAmountCents < 0).length;
  } on Object {
    owing = 0;
  }
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: Text(l10n.archiveGroupConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.archiveGroupConfirmMessage),
          if (owing > 0) ...[
            const SizedBox(height: 12),
            Text(
              l10n.archiveGroupUnsettled(owing),
              style: TextStyle(color: Theme.of(dCtx).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: dCtx.tracked(
              TelemetryEvent.tapDialogCancel, () => Navigator.pop(dCtx, false)),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: dCtx.tracked(
              TelemetryEvent.tapDialogConfirm, () => Navigator.pop(dCtx, true)),
          child: Text(l10n.archiveGroup),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final result =
      await ref.read(groupProvider.notifier).setArchived(group.id, true);
  messenger.showSnackBar(SnackBar(
    content: Text(result.fold(
      (failure) => failureMessage(failure, l10n),
      (_) => l10n.groupArchived,
    )),
  ));
}

/// Reopens an archived group, so it can be changed again.
Future<void> reopenGroup(
    BuildContext context, WidgetRef ref, Group group) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final result =
      await ref.read(groupProvider.notifier).setArchived(group.id, false);
  messenger.showSnackBar(SnackBar(
    content: Text(result.fold(
      (failure) => failureMessage(failure, l10n),
      (_) => l10n.groupReopened,
    )),
  ));
}

/// Shown at the top of an archived group: it is read-only, and its owner can
/// reopen it.
class ArchivedGroupBanner extends ConsumerWidget {
  const ArchivedGroupBanner({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.groupArchivedBanner)),
            if (canArchiveGroup(ref, group))
              TextButton(
                onPressed: context.tracked(TelemetryEvent.tapReopenGroup,
                    () => reopenGroup(context, ref, group)),
                child: Text(l10n.reopenGroup),
              ),
          ],
        ),
      ),
    );
  }
}
