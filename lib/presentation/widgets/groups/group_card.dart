import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/member_initial.dart';
import 'package:simsplit/presentation/widgets/common/money_text.dart';

class GroupCard extends ConsumerWidget {
  const GroupCard({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final members = ref.watch(memberListProvider(group.id)).value ?? [];
    final myMember = members.where((m) => m.isMe).firstOrNull;
    final myNet = myMember == null
        ? null
        : ref
            .watch(debtSummaryProvider(group.id, group.currencyCode))
            .value
            ?.balances
            .where((b) => b.member.id == myMember.id)
            .firstOrNull
            ?.netAmountCents;

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/groups/${group.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              GroupGlyph(group: group),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${l10n.peopleCount(members.length)} · ${group.currencyCode}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (myNet != null) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (myNet != 0)
                      MoneyText(
                        myNet.abs(),
                        group.currencyCode,
                        color: context.money.forSign(myNet, cs),
                        style: theme.textTheme.titleSmall,
                      ),
                    Text(
                      myNet > 0
                          ? l10n.statusOwedToYou
                          : myNet < 0
                              ? l10n.statusYouOwe
                              : l10n.statusSettled,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The group's emoji (or initial) in a rounded square.
class GroupGlyph extends StatelessWidget {
  const GroupGlyph({super.key, required this.group, this.size = 48});

  final Group group;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final emoji = group.emoji;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        emoji ?? nameInitial(group.name),
        style: TextStyle(
          fontSize: emoji != null ? size * 0.5 : size * 0.4,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),
    );
  }
}
