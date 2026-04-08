import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';

class GroupCard extends ConsumerWidget {
  const GroupCard({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final members = ref.watch(memberListProvider(group.id)).valueOrNull ?? [];
    final memberCount = members.length;
    final myMember = members.where((m) => m.isMe).firstOrNull;

    final debtAsync =
        ref.watch(debtSummaryProvider(group.id, group.currencyCode));
    final myBalance = myMember == null
        ? null
        : debtAsync.valueOrNull?.balances
            .where((b) => b.member.id == myMember.id)
            .firstOrNull;

    return Dismissible(
      key: ValueKey(group.id),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.edit, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              l10n.edit,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        await context.push('/groups/${group.id}/edit');
        return false;
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Color(group.colorValue),
            child: Text(
              group.emoji ?? group.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(fontSize: 18),
            ),
          ),
          title: Text(group.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.memberCountLabel(memberCount, group.currencyCode),
                style: const TextStyle(color: Colors.grey),
              ),
              if (myMember != null && myBalance != null) ...[
                const SizedBox(height: 2),
                _BalanceLabel(
                  netCents: myBalance.netAmountCents,
                  currencyCode: group.currencyCode,
                  l10n: l10n,
                ),
              ],
            ],
          ),
          isThreeLine: myMember != null && myBalance != null,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/groups/${group.id}'),
        ),
      ),
    );
  }
}

class _BalanceLabel extends StatelessWidget {
  const _BalanceLabel({
    required this.netCents,
    required this.currencyCode,
    required this.l10n,
  });

  final int netCents;
  final String currencyCode;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (netCents > 0) {
      return Text(
        l10n.youAreOwed(formatMoney(netCents, currencyCode)),
        style: const TextStyle(
          color: Colors.green,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      );
    } else if (netCents < 0) {
      return Text(
        l10n.youOwe(formatMoney(netCents.abs(), currencyCode)),
        style: const TextStyle(
          color: Colors.red,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      );
    } else {
      return Text(
        l10n.evenBalance,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
        ),
      );
    }
  }
}
