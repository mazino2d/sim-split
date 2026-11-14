import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/split_report.dart';

/// Money in shared output: "đ" rather than "₫", which common chat fonts
/// render too small (#115).
String shareMoney(int cents, String currencyCode) =>
    formatMoney(cents, currencyCode).replaceAll('₫', 'đ');

/// The group's title with its emoji.
String splitTitle(SplitReport r, AppLocalizations l10n) =>
    l10n.splitTitle('${r.group.emoji ?? ''} ${r.group.name}'.trim());

/// What a member does with the collector, as in the image: a plain number
/// is sent to the collector, a number in parentheses comes back.
String collectorCell(SplitReport r, int cents, String currencyCode) =>
    cents == 0
        ? '–'
        : cents > 0
            ? shareMoney(cents, currencyCode)
            : '(${shareMoney(-cents, currencyCode)})';

/// How the group settles, as lines: the "send to" column in hub mode with
/// the collector's reconciliation, or the transfers otherwise.
List<String> settleLines(SplitReport r, AppLocalizations l10n) {
  final currency = r.group.currencyCode;
  if (r.transfers.isEmpty) {
    return [
      r.mode == SettlementMode.hub &&
              r.collector == null &&
              r.balances.any((b) => b.netAmountCents != 0)
          ? l10n.splitNoCollector
          : l10n.splitAllSettled,
    ];
  }
  final collector = r.collector;
  if (r.mode == SettlementMode.hub && collector != null) {
    final money = r.collectorMoney;
    return [
      '${l10n.splitColSendTo(collector.name)}:',
      for (final m in r.members)
        if (m.id != collector.id && r.toCollector(m) != 0)
          '  ${m.name}: ${collectorCell(r, r.toCollector(m), currency)}',
      l10n.splitLegend(collector.name),
      l10n.splitCollectorMoney(
        collector.name,
        shareMoney(money.collects, currency),
        shareMoney(money.refunds, currency),
        shareMoney(money.keeps, currency),
      ),
    ];
  }
  return [
    for (final t in r.transfers)
      l10n.splitTransfer(
          t.from.name, t.to.name, shareMoney(t.amountCents, currency)),
  ];
}

/// The split as plain text, for chats that compress images (#115).
String splitReportText(SplitReport r, AppLocalizations l10n) {
  final currency = r.group.currencyCode;
  return [
    splitTitle(r, l10n),
    l10n.splitSubtitle(shareMoney(r.totalCents, currency), r.rows.length),
    '',
    for (final b in r.balances)
      l10n.splitTextMember(
        b.member.name,
        shareMoney(b.shareCents, currency),
        shareMoney(b.paidCents, currency),
      ),
    '',
    ...settleLines(r, l10n),
  ].join('\n');
}
