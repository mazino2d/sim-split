import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/notifiers/group_notifier.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
import 'package:simsplit/presentation/utils/tracking.dart';
import 'package:simsplit/presentation/widgets/common/member_avatar.dart';
import 'package:simsplit/presentation/utils/member_label.dart';

/// Opens the choice of how a group settles up (#116).
Future<void> showSettlementModeSheet(BuildContext context, String groupId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SettlementModeSheet(groupId: groupId),
    );

/// "Through one person" (with the collector) or "Fewest transfers". A choice
/// is saved at once and shared with every member of the group.
class SettlementModeSheet extends ConsumerWidget {
  const SettlementModeSheet({super.key, required this.groupId});

  final String groupId;

  Future<void> _set(
    BuildContext context,
    WidgetRef ref,
    SettlementMode mode,
    String? hubMemberId,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(groupProvider.notifier).setSettlementMode(
          groupId: groupId,
          mode: mode,
          hubMemberId: hubMemberId,
        );
    result.fold(
      (failure) => messenger
          .showSnackBar(SnackBar(content: Text(failureMessage(failure, l10n)))),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final group = ref.watch(liveGroupProvider(groupId)).value;
    if (group == null) return const SizedBox.shrink();
    final members = ref.watch(memberListProvider(groupId)).value ?? const [];
    final collector = ref
        .watch(debtSummaryProvider(groupId, group.currencyCode))
        .value
        ?.collector;
    final hub = group.settlementMode == SettlementMode.hub;

    String name(Member m) => m.label(l10n);

    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l10n.settlementModeTitle,
                  style: theme.textTheme.titleMedium),
            ),
            _ModeTile(
              selected: hub,
              title: l10n.settleThroughOne,
              subtitle: l10n.settleThroughOneHint,
              onTap: context.tracked(
                  TelemetryEvent.tapPickSettlementMode,
                  () => _set(context, ref, SettlementMode.hub,
                      group.settlementHubMemberId)),
            ),
            if (hub) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 4, 16, 4),
                child: Text(l10n.collector,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              for (final member in members)
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 56, right: 16),
                  leading: MemberAvatar(member: member, size: 32),
                  title: Text(name(member),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: member.linkedUid != null &&
                          member.linkedUid == group.ownerUid
                      ? Text(l10n.groupOwner)
                      : null,
                  trailing: member.id == collector?.id
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: context.tracked(TelemetryEvent.tapPickCollector,
                      () => _set(context, ref, SettlementMode.hub, member.id)),
                ),
            ],
            _ModeTile(
              selected: !hub,
              title: l10n.settleFewestTransfers,
              subtitle: l10n.settleFewestTransfersHint,
              onTap: context.tracked(TelemetryEvent.tapPickSettlementMode,
                  () => _set(context, ref, SettlementMode.simplified, null)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "How to settle up" in Edit group: the group's mode and collector, which
/// open [SettlementModeSheet] to change them.
class SettlementModeTile extends ConsumerWidget {
  const SettlementModeTile({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final group = ref.watch(liveGroupProvider(groupId)).value;
    if (group == null) return const SizedBox.shrink();
    final hub = group.settlementMode == SettlementMode.hub;
    final collector = hub
        ? ref
            .watch(debtSummaryProvider(groupId, group.currencyCode))
            .value
            ?.collector
        : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(hub ? Icons.hub_outlined : Icons.swap_horiz_rounded),
      title: Text(hub ? l10n.settleThroughOne : l10n.settleFewestTransfers),
      subtitle: Text(!hub
          ? l10n.settleFewestTransfersHint
          : collector == null
              ? l10n.pickCollectorHint
              : l10n.settlingThrough(collector.labelInSentence(l10n))),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: context.tracked(TelemetryEvent.tapOpenSettlementMode,
          () => showSettlementModeSheet(context, groupId)),
    );
  }
}

/// The settlement mode picked while creating a group: "Through one person"
/// (the default, with the creator as collector) or "Fewest transfers".
class NewGroupSettlementModePicker extends StatelessWidget {
  const NewGroupSettlementModePicker({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final SettlementMode mode;
  final ValueChanged<SettlementMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _ModeTile(
          selected: mode == SettlementMode.hub,
          title: l10n.settleThroughOne,
          subtitle: l10n.settleThroughOneHint,
          onTap: context.trackedCall(TelemetryEvent.tapPickSettlementMode,
              () => onChanged(SettlementMode.hub)),
        ),
        _ModeTile(
          selected: mode == SettlementMode.simplified,
          title: l10n.settleFewestTransfers,
          subtitle: l10n.settleFewestTransfersHint,
          onTap: context.trackedCall(TelemetryEvent.tapPickSettlementMode,
              () => onChanged(SettlementMode.simplified)),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(selected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked),
        title: Text(title),
        subtitle: Text(subtitle),
        selected: selected,
        onTap: onTap,
      );
}
