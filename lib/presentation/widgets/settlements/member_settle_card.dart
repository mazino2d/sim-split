import 'package:flutter/material.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/member_label.dart';
import 'package:simsplit/presentation/widgets/common/money_text.dart';

/// One member on the Settlements tab: what their share was, what they paid,
/// what is left to settle, then the transfers they make (each with Settle)
/// or who they wait for. "Who pays whom" and the balances in one place.
class MemberSettleCard extends StatelessWidget {
  const MemberSettleCard({
    super.key,
    required this.balance,
    required this.currencyCode,
    this.outgoing = const [],
    this.waitingFor = const [],
    this.collector,
    this.onSettle,
  });

  final MemberBalance balance;
  final String currencyCode;

  /// The transfers this member makes.
  final List<Debt> outgoing;

  /// Who pays this member, when they wait to be paid back.
  final List<Member> waitingFor;

  /// What the collector receives and pays back; null for everyone else.
  final ({int collects, int paysBack})? collector;

  /// Opens the settle form for a transfer; null hides Settle (archived).
  final ValueChanged<Debt>? onSettle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelStyle =
        theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant);
    final valueStyle = theme.textTheme.bodyMedium;
    final netCents = balance.netAmountCents;

    Widget line(String label, Widget value) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(child: Text(label, style: labelStyle)),
              const SizedBox(width: 12),
              value,
            ],
          ),
        );

    // Left to settle is the balance seen from the member's side: ↑ (red)
    // means they still pay, ↓ (green) means they wait to be paid back.
    final toSettle = -netCents;
    final color = context.money.forSign(netCents, cs);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              collector == null
                  ? balance.member.label(l10n)
                  : '${balance.member.label(l10n)} · ${l10n.collectorTag}',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Column(
              children: [
                line(
                    l10n.balanceRowShare,
                    MoneyText(balance.shareCents, currencyCode,
                        style: valueStyle)),
                line(
                    l10n.balanceRowPaid,
                    MoneyText(balance.paidCents, currencyCode,
                        style: valueStyle)),
                if (balance.settledCents != 0)
                  line(
                      l10n.balanceRowSettled,
                      MoneyText(balance.settledCents, currencyCode,
                          style: valueStyle)),
                line(
                  l10n.balanceRowToSettle,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (toSettle != 0)
                        Icon(
                          toSettle > 0
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 16,
                          color: color,
                          semanticLabel: toSettle > 0
                              ? l10n.balanceStillPays
                              : l10n.balanceWaitsToBePaid,
                        ),
                      MoneyText(
                        toSettle.abs(),
                        currencyCode,
                        color: color,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (toSettle == 0 &&
                          outgoing.isEmpty &&
                          collector == null) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.check_rounded,
                            size: 16, color: context.money.positive),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (collector case final money?)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 4),
              child: Text(
                l10n.collectorMoneyLine(
                  formatMoney(money.collects, currencyCode),
                  formatMoney(money.paysBack, currencyCode),
                ),
                style: labelStyle,
              ),
            ),
          for (final debt in outgoing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.arrow_forward_rounded,
                      size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  // The receiver wraps instead of being cut.
                  Expanded(
                    child: Text(debt.to.label(l10n),
                        style: theme.textTheme.bodyLarge),
                  ),
                  const SizedBox(width: 8),
                  MoneyText(debt.amountCents, currencyCode,
                      style: theme.textTheme.titleSmall),
                  if (onSettle != null) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          onSettle!(debt), // telemetry: tracked by the caller
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: Text(l10n.settle),
                    ),
                  ],
                ],
              ),
            ),
          if (waitingFor.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.arrow_back_rounded,
                        size: 18, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.waitingFor(
                          waitingFor.map((m) => m.label(l10n)).join(', ')),
                      style: labelStyle,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The members of a settlements list in the order they are shown: you, then
/// who still pays (the most first), the collector, who waits to be paid back
/// (the most first), and who is settled.
List<MemberBalance> orderForSettling(DebtSummary summary) {
  final collectorId =
      summary.mode == SettlementMode.hub ? summary.collector?.id : null;
  final payers = {for (final d in summary.suggestions) d.from.id};
  int rank(MemberBalance b) {
    if (b.member.isMe) return 0;
    if (b.member.id == collectorId) return 2;
    if (payers.contains(b.member.id) || b.netAmountCents < 0) return 1;
    if (b.netAmountCents > 0) return 3;
    return 4;
  }

  final ordered = [...summary.balances];
  // A stable sort keeps the group's member order within a rank and amount.
  _stableSort(ordered, (a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    // Payers: most negative first; receivers: most positive first.
    return rank(a) == 1
        ? a.netAmountCents.compareTo(b.netAmountCents)
        : b.netAmountCents.compareTo(a.netAmountCents);
  });
  return ordered;
}

/// Insertion-based stable sort, enough for a group's handful of members.
void _stableSort<T>(List<T> list, int Function(T, T) compare) {
  for (var i = 1; i < list.length; i++) {
    final item = list[i];
    var j = i - 1;
    while (j >= 0 && compare(list[j], item) > 0) {
      list[j + 1] = list[j];
      j--;
    }
    list[j + 1] = item;
  }
}
