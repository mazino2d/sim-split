import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/expense.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';

/// One expense in the shared split (#115): who paid, how much, and each
/// member's part of it.
class SplitReportRow {
  const SplitReportRow({
    required this.title,
    required this.paidBy,
    required this.amountCents,
    required this.shares,
  });

  final String title;
  final Member paidBy;
  final int amountCents;

  /// Member ID → their part; members not in the expense are absent.
  final Map<String, int> shares;
}

/// Everything the shared image and text show (#115), worked out from the
/// same balances and suggestions as the app, so the last row follows the
/// group's settlement mode (#116).
class SplitReport {
  const SplitReport({
    required this.group,
    required this.rows,
    required this.balances,
    required this.mode,
    required this.collector,
    required this.transfers,
  });

  final Group group;
  final List<SplitReportRow> rows;

  /// One per member, in the group's member order: paid, share, settled, net.
  final List<MemberBalance> balances;
  final SettlementMode mode;

  /// Who everyone settles with in [SettlementMode.hub].
  final Member? collector;

  /// The suggested transfers that settle everyone.
  final List<Debt> transfers;

  List<Member> get members => [for (final b in balances) b.member];

  int get totalCents => rows.fold(0, (sum, r) => sum + r.amountCents);

  /// In hub mode, what each member sends the collector (positive) or gets
  /// back from them (negative); 0 for the collector and members who are
  /// even.
  int toCollector(Member member) {
    final c = collector;
    if (c == null) return 0;
    var cents = 0;
    for (final t in transfers) {
      if (t.from.id == member.id && t.to.id == c.id) cents += t.amountCents;
      if (t.to.id == member.id && t.from.id == c.id) cents -= t.amountCents;
    }
    return cents;
  }

  /// What the collector receives, pays back and keeps: the difference is
  /// exactly what they overpaid.
  ({int collects, int refunds, int keeps}) get collectorMoney {
    var collects = 0;
    var refunds = 0;
    for (final m in members) {
      final cents = toCollector(m);
      if (cents > 0) collects += cents;
      if (cents < 0) refunds -= cents;
    }
    return (collects: collects, refunds: refunds, keeps: collects - refunds);
  }
}

/// Builds the shared split from the group's expenses and its debt summary.
/// Deleted expenses are left out; the rest are in date order.
SplitReport buildSplitReport({
  required Group group,
  required List<Expense> expenses,
  required DebtSummary summary,
}) {
  final byId = {for (final b in summary.balances) b.member.id: b.member};
  final live = expenses.where((e) => !e.isDeleted).toList()
    ..sort((a, b) {
      final byDate = a.expenseDate.compareTo(b.expenseDate);
      return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
    });
  return SplitReport(
    group: group,
    rows: [
      for (final e in live)
        if (byId[e.paidByMemberId] case final payer?)
          SplitReportRow(
            title: e.title,
            paidBy: payer,
            amountCents: e.amountCents,
            shares: {
              for (final s in e.splits)
                if (s.amountCents != 0) s.memberId: s.amountCents,
            },
          ),
    ],
    balances: summary.balances,
    mode: summary.mode,
    collector: summary.collector,
    transfers: summary.suggestions,
  );
}

/// [items] in pages of at most [size].
List<List<T>> pagesOf<T>(List<T> items, int size) => [
      for (var i = 0; i < items.length; i += size)
        items.sublist(i, i + size > items.length ? items.length : i + size),
    ];
