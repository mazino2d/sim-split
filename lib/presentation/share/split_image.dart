import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/split_report.dart';
import 'package:simsplit/presentation/share/split_text.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';

// The shared split as images, drawn on the device (#115): nothing leaves it
// until the user shares. A summary card readable at phone width comes first,
// then the expenses, at most [_rowsPerPage] rows and [_membersPerBand]
// member columns per image so no image has to be zoomed in a chat.

const _rowsPerPage = 30;
const _membersPerBand = 5;
const _margin = 60.0;
const _cellPad = 14.0;

// A fixed light palette: images are read in chat apps, not in the app.
const _paper = Color(0xFFFFFFFF);
const _ink = Color(0xFF1B1B1F);
const _muted = Color(0xFF5F6368);
const _headerBg = Color(0xFF263238);
const _headerInk = Color(0xFFFFFFFF);
const _zebra = Color(0xFFF3F4F6);
const _totalBg = Color(0xFFE8EAED);
const _pay = Color(0xFFC62828);
const _payBg = Color(0xFFFFEBEE);
const _getBack = Color(0xFF2E7D32);
const _getBackBg = Color(0xFFE8F5E9);

class _Cell {
  const _Cell(this.text, {this.sub, this.bold = false, this.color});

  final String text;
  final String? sub;
  final bool bold;
  final Color? color;
}

class _Row {
  const _Row(this.cells, {this.background, this.bold = false, this.highlight});

  final List<_Cell> cells;
  final Color? background;
  final bool bold;

  /// Background of the last cell (the "send to" column).
  final Color? highlight;
}

TextStyle _style(double size, {bool bold = false, Color color = _ink}) =>
    TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: size,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );

TextPainter _layout(String text, TextStyle style, double maxWidth,
        {int? maxLines = 1, TextAlign align = TextAlign.left}) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);

/// One table image: a title, a subtitle, a header row, rows and notes.
Future<Uint8List> _tableImage({
  required String title,
  required String subtitle,
  required List<double> widths,
  required List<bool> numeric,
  required List<String> header,
  required List<_Row> rows,
  List<String> notes = const [],
}) async {
  final width = _margin * 2 + widths.fold(0.0, (a, b) => a + b);
  final inner = width - _margin * 2;
  final titlePainter = _layout(title, _style(44, bold: true), inner);
  final subtitlePainter =
      _layout(subtitle, _style(28, color: _muted), inner, maxLines: 2);
  final notePainters = [
    for (final n in notes) _layout(n, _style(26), inner, maxLines: null),
  ];
  const headerHeight = 64.0;
  double rowHeight(_Row r) => r.cells.any((c) => c.sub != null) ? 84 : 60;

  final height = _margin +
      titlePainter.height +
      8 +
      subtitlePainter.height +
      32 +
      headerHeight +
      rows.fold(0.0, (sum, r) => sum + rowHeight(r)) +
      (notes.isEmpty ? 0 : 24) +
      notePainters.fold(0.0, (sum, p) => sum + p.height + 10) +
      48 +
      _margin;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = _paper);

  var y = _margin;
  titlePainter.paint(canvas, Offset(_margin, y));
  y += titlePainter.height + 8;
  subtitlePainter.paint(canvas, Offset(_margin, y));
  y += subtitlePainter.height + 32;

  void paintCells(List<_Cell> cells, double top, double rowH,
      {required Color ink, bool bold = false, double size = 28}) {
    var x = _margin;
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final w = widths[i] - _cellPad * 2;
      final align = numeric[i] ? TextAlign.right : TextAlign.left;
      final main = _layout(cell.text,
          _style(size, bold: bold || cell.bold, color: cell.color ?? ink), w,
          align: align);
      final sub = cell.sub == null
          ? null
          : _layout(cell.sub!, _style(22, color: _muted), w, align: align);
      final contentH = main.height + (sub == null ? 0 : sub.height + 2);
      var ty = top + (rowH - contentH) / 2;
      double dx(TextPainter p) => x + _cellPad + (numeric[i] ? w - p.width : 0);
      main.paint(canvas, Offset(dx(main), ty));
      if (sub != null) {
        ty += main.height + 2;
        sub.paint(canvas, Offset(dx(sub), ty));
      }
      x += widths[i];
    }
  }

  canvas.drawRect(Rect.fromLTWH(_margin, y, inner, headerHeight),
      Paint()..color = _headerBg);
  paintCells([for (final h in header) _Cell(h)], y, headerHeight,
      ink: _headerInk, bold: true, size: 24);
  y += headerHeight;

  for (final (i, row) in rows.indexed) {
    final h = rowHeight(row);
    final bg = row.background ?? (i.isOdd ? _zebra : _paper);
    canvas.drawRect(Rect.fromLTWH(_margin, y, inner, h), Paint()..color = bg);
    if (row.highlight case final color?) {
      canvas.drawRect(
          Rect.fromLTWH(width - _margin - widths.last, y, widths.last, h),
          Paint()..color = color);
    }
    paintCells(row.cells, y, h, ink: _ink, bold: row.bold);
    y += h;
  }

  if (notes.isNotEmpty) y += 24;
  for (final p in notePainters) {
    p.paint(canvas, Offset(_margin, y));
    y += p.height + 10;
  }
  final brand = _layout('SimSplit', _style(22, color: _muted), inner);
  brand.paint(canvas, Offset(width - _margin - brand.width, height - _margin));

  final image =
      await recorder.endRecording().toImage(width.ceil(), (height + 32).ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// The summary card: each member's share, what they paid, and what they
/// send to (or get back from) the collector, or their net.
Future<Uint8List> _summaryImage(SplitReport r, AppLocalizations l10n) {
  final currency = r.group.currencyCode;
  String money(int cents) => shareMoney(cents, currency);
  final collector = r.mode == SettlementMode.hub ? r.collector : null;
  final settled = r.balances.any((b) => b.settledCents != 0);

  final widths = settled
      ? [280.0, 170.0, 170.0, 170.0, 170.0]
      : [330.0, 200.0, 200.0, 230.0];
  final header = [
    l10n.splitColMember,
    l10n.splitColShare,
    l10n.splitColPaid,
    if (settled) l10n.splitColSettled,
    collector == null ? l10n.splitColNet : l10n.splitColSendTo(collector.name),
  ];

  _Row memberRow(int i) {
    final b = r.balances[i];
    final isCollector = b.member.id == collector?.id;
    final last = collector == null ? b.netAmountCents : r.toCollector(b.member);
    final lastCell = collector == null
        ? _Cell(last == 0 ? '–' : '${last > 0 ? '+' : '−'}${money(last.abs())}',
            bold: true, color: last > 0 ? _getBack : (last < 0 ? _pay : _ink))
        : isCollector
            ? _Cell(l10n.splitCollector, color: _muted)
            : _Cell(collectorCell(r, last, currency),
                bold: true,
                color: last > 0 ? _pay : (last < 0 ? _getBack : _ink));
    return _Row(
      [
        _Cell(b.member.name, bold: isCollector),
        _Cell(money(b.shareCents)),
        _Cell(b.paidCents == 0 ? '–' : money(b.paidCents)),
        if (settled)
          _Cell(b.settledCents == 0
              ? '–'
              : '${b.settledCents > 0 ? '+' : '−'}'
                  '${money(b.settledCents.abs())}'),
        lastCell,
      ],
      background: i.isOdd ? _zebra : _paper,
      highlight: collector == null || isCollector || last == 0
          ? null
          : (last > 0 ? _payBg : _getBackBg),
    );
  }

  final totalShare = r.balances.fold(0, (s, b) => s + b.shareCents);
  final totalPaid = r.balances.fold(0, (s, b) => s + b.paidCents);
  return _tableImage(
    title: splitTitle(r, l10n),
    subtitle: l10n.splitSubtitle(money(r.totalCents), r.rows.length),
    widths: widths,
    numeric: [false, for (var i = 1; i < widths.length; i++) true],
    header: header,
    rows: [
      for (var i = 0; i < r.balances.length; i++) memberRow(i),
      _Row(
        [
          _Cell(l10n.splitRowTotalShare),
          _Cell(money(totalShare)),
          _Cell(money(totalPaid)),
          if (settled) const _Cell(''),
          const _Cell(''),
        ],
        background: _totalBg,
        bold: true,
      ),
    ],
    notes: collector == null
        ? settleLines(r, l10n)
        : [
            l10n.splitLegend(collector.name),
            if (r.transfers.isNotEmpty)
              l10n.splitCollectorMoney(
                collector.name,
                money(r.collectorMoney.collects),
                money(r.collectorMoney.refunds),
                money(r.collectorMoney.keeps),
              ),
          ],
  );
}

/// The expenses: one row each, one column per member with their part, and
/// the column totals on the last page so every column can be checked.
Future<List<Uint8List>> _detailImages(
    SplitReport r, AppLocalizations l10n) async {
  if (r.rows.isEmpty) return const [];
  final currency = r.group.currencyCode;
  String money(int cents) => shareMoney(cents, currency);
  final bands = pagesOf(r.balances, _membersPerBand);
  final pages =
      pagesOf([for (final (i, row) in r.rows.indexed) (i, row)], _rowsPerPage);
  final total = bands.length * pages.length;
  final images = <Uint8List>[];
  var n = 0;
  for (final band in bands) {
    for (final (p, page) in pages.indexed) {
      n++;
      final widths = [70.0, 420.0, 200.0, for (final _ in band) 190.0];
      images.add(await _tableImage(
        title: l10n.splitDetailTitle(
            '${r.group.emoji ?? ''} ${r.group.name}'.trim(), n, total),
        subtitle: l10n.splitSubtitle(money(r.totalCents), r.rows.length),
        widths: widths,
        numeric: [false, false, true, for (final _ in band) true],
        header: [
          '#',
          l10n.splitColExpense,
          l10n.splitColAmount,
          for (final b in band) b.member.name,
        ],
        rows: [
          for (final (i, row) in page)
            _Row([
              _Cell('${i + 1}', color: _muted),
              _Cell(row.title, sub: l10n.splitPaidBy(row.paidBy.name)),
              _Cell(money(row.amountCents)),
              for (final b in band)
                _Cell(
                  row.shares[b.member.id] == null
                      ? '–'
                      : money(row.shares[b.member.id]!),
                  bold: row.paidBy.id == b.member.id,
                  color: row.shares[b.member.id] == null ? _muted : null,
                ),
            ]),
          if (p == pages.length - 1) ...[
            _Row([
              const _Cell(''),
              _Cell(l10n.splitRowTotalShare),
              _Cell(money(r.totalCents)),
              for (final b in band) _Cell(money(b.shareCents)),
            ], background: _totalBg, bold: true),
            _Row([
              const _Cell(''),
              _Cell(l10n.splitRowPaid),
              const _Cell(''),
              for (final b in band)
                _Cell(b.paidCents == 0 ? '–' : money(b.paidCents)),
            ], background: _totalBg, bold: true),
          ],
        ],
      ));
    }
  }
  return images;
}

/// The split as PNG images: the summary card, then the expenses.
Future<List<Uint8List>> renderSplitImages(
        SplitReport report, AppLocalizations l10n) async =>
    [
      await _summaryImage(report, l10n),
      ...await _detailImages(report, l10n),
    ];
