import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/split_report.dart';
import 'package:simsplit/presentation/share/split_text.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';

// The shared split as one long image, drawn on the device (#115): nothing
// leaves it until the user shares. The summary comes first, then every
// expense. No text is cut: long names and titles wrap and their row grows.
// Expense tables take at most [_membersPerBand] member columns so the image
// stays readable at phone width; more members get another table below.
// Only a split taller than [_maxImageHeight] continues in a second image,
// because phones cannot draw an image of any size.

const _membersPerBand = 5;
const _maxImageHeight = 12000.0;
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

/// Text laid out to [maxWidth], wrapping onto as many lines as it needs.
TextPainter _layout(String text, TextStyle style, double maxWidth,
        {TextAlign align = TextAlign.left}) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth);

/// A piece of the image, drawn top to bottom.
abstract class _Block {
  double get height;
  void paint(Canvas canvas, double y);
}

class _Gap implements _Block {
  const _Gap(this.height);

  @override
  final double height;

  @override
  void paint(Canvas canvas, double y) {}
}

class _TextBlock implements _Block {
  _TextBlock(String text, TextStyle style, double width, {this.gapAfter = 0})
      : painter = _layout(text, style, width);

  final TextPainter painter;
  final double gapAfter;

  @override
  double get height => painter.height + gapAfter;

  @override
  void paint(Canvas canvas, double y) =>
      painter.paint(canvas, Offset(_margin, y));
}

/// One table row; its height follows its tallest cell.
class _RowBlock implements _Block {
  _RowBlock(
    this.widths,
    this.numeric,
    _Row row, {
    required Color background,
    Color ink = _ink,
    double size = 28,
    double minHeight = 60,
    this.header,
  })  : _background = background,
        _highlight = row.highlight {
    for (var i = 0; i < row.cells.length; i++) {
      final cell = row.cells[i];
      final w = widths[i] - _cellPad * 2;
      final align = numeric[i] ? TextAlign.right : TextAlign.left;
      _main.add(_layout(
          cell.text,
          _style(size, bold: row.bold || cell.bold, color: cell.color ?? ink),
          w,
          align: align));
      _sub.add(cell.sub == null
          ? null
          : _layout(cell.sub!, _style(22, color: _muted), w, align: align));
    }
    var content = 0.0;
    for (var i = 0; i < _main.length; i++) {
      content = math.max(content,
          _main[i].height + (_sub[i] == null ? 0 : _sub[i]!.height + 2));
    }
    height = math.max(minHeight, content + 2 * 16);
  }

  final List<double> widths;
  final List<bool> numeric;

  /// The table's header row, repeated when the table continues in the next
  /// image; null for the header itself.
  final _RowBlock? header;
  final Color _background;
  final Color? _highlight;
  final _main = <TextPainter>[];
  final _sub = <TextPainter?>[];

  @override
  late final double height;

  double get width => widths.fold(0.0, (a, b) => a + b);

  @override
  void paint(Canvas canvas, double y) {
    canvas.drawRect(
        Rect.fromLTWH(_margin, y, width, height), Paint()..color = _background);
    if (_highlight case final color?) {
      canvas.drawRect(
          Rect.fromLTWH(_margin + width - widths.last, y, widths.last, height),
          Paint()..color = color);
    }
    var x = _margin;
    for (var i = 0; i < _main.length; i++) {
      final w = widths[i] - _cellPad * 2;
      final main = _main[i];
      final sub = _sub[i];
      final contentH = main.height + (sub == null ? 0 : sub.height + 2);
      var ty = y + (height - contentH) / 2;
      double dx(TextPainter p) => x + _cellPad + (numeric[i] ? w - p.width : 0);
      main.paint(canvas, Offset(dx(main), ty));
      if (sub != null) {
        ty += main.height + 2;
        sub.paint(canvas, Offset(dx(sub), ty));
      }
      x += widths[i];
    }
  }
}

/// A table as blocks: the header, then one block per row.
List<_RowBlock> _table({
  required List<double> widths,
  required List<bool> numeric,
  required List<String> header,
  required List<_Row> rows,
}) {
  final head = _RowBlock(
      widths, numeric, _Row([for (final h in header) _Cell(h)]),
      background: _headerBg, ink: _headerInk, size: 24, minHeight: 64);
  return [
    head,
    for (final (i, row) in rows.indexed)
      _RowBlock(widths, numeric, row,
          background: row.background ?? (i.isOdd ? _zebra : _paper),
          header: head),
  ];
}

/// Spreads [blocks] over as few images as fit [_maxImageHeight], repeating
/// a table's header when it continues in the next image.
List<List<_Block>> _paginate(List<_Block> blocks) {
  const room = _maxImageHeight - _margin * 2 - 48;
  final pages = <List<_Block>>[[]];
  var used = 0.0;
  for (final (i, block) in blocks.indexed) {
    // Keep a header together with the first row under it.
    final needed = block is _RowBlock && block.header == null
        ? block.height + (i + 1 < blocks.length ? blocks[i + 1].height : 0)
        : block.height;
    if (used + needed > room && pages.last.isNotEmpty) {
      pages.add([]);
      used = 0;
      final head = block is _RowBlock ? block.header : null;
      if (head != null) {
        pages.last.add(head);
        used += head.height;
      }
    }
    pages.last.add(block);
    used += block.height;
  }
  return pages;
}

Future<Uint8List> _draw(List<_Block> blocks, double width) async {
  final contentHeight = blocks.fold(0.0, (sum, b) => sum + b.height);
  final height = _margin + contentHeight + 48 + _margin;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = _paper);
  var y = _margin;
  for (final block in blocks) {
    block.paint(canvas, y);
    y += block.height;
  }
  final brand =
      _layout('SimSplit', _style(22, color: _muted), width - _margin * 2);
  brand.paint(
      canvas, Offset(width - _margin - brand.width, height - _margin - 24));
  final image =
      await recorder.endRecording().toImage(width.ceil(), height.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// The summary: each member's share, what they paid, and what they send to
/// (or get back from) the collector, or their net; then the notes.
({List<_RowBlock> table, List<String> notes}) _summary(
    SplitReport r, AppLocalizations l10n) {
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
  return (
    table: _table(
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
    ),
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
/// the column totals so every column can be checked.
List<List<_RowBlock>> _expenseTables(SplitReport r, AppLocalizations l10n) {
  if (r.rows.isEmpty) return const [];
  final currency = r.group.currencyCode;
  String money(int cents) => shareMoney(cents, currency);
  return [
    for (final band in pagesOf(r.balances, _membersPerBand))
      _table(
        widths: [70.0, 420.0, 200.0, for (final _ in band) 190.0],
        numeric: [false, false, true, for (final _ in band) true],
        header: [
          '#',
          l10n.splitColExpense,
          l10n.splitColAmount,
          for (final b in band) b.member.name,
        ],
        rows: [
          for (final (i, row) in r.rows.indexed)
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
      ),
  ];
}

/// The split as PNG: one long image with the summary and every expense, or
/// more only when it is too tall for one.
Future<List<Uint8List>> renderSplitImages(
    SplitReport report, AppLocalizations l10n) async {
  final summary = _summary(report, l10n);
  final expenses = _expenseTables(report, l10n);
  final tableWidth = [summary.table, ...expenses]
      .map((t) => t.first.width)
      .fold(0.0, math.max);
  final width = _margin * 2 + math.max(tableWidth, 960);
  final inner = width - _margin * 2;
  final currency = report.group.currencyCode;
  final blocks = <_Block>[
    _TextBlock(splitTitle(report, l10n), _style(44, bold: true), inner,
        gapAfter: 8),
    _TextBlock(
        l10n.splitSubtitle(
            shareMoney(report.totalCents, currency), report.rows.length),
        _style(28, color: _muted),
        inner,
        gapAfter: 32),
    ...summary.table,
    if (summary.notes.isNotEmpty) const _Gap(24),
    for (final n in summary.notes)
      _TextBlock(n, _style(26), inner, gapAfter: 10),
    if (expenses.isNotEmpty) ...[
      const _Gap(40),
      _TextBlock(l10n.expenses, _style(36, bold: true), inner, gapAfter: 16),
      for (final (i, table) in expenses.indexed) ...[
        if (i > 0) const _Gap(32),
        ...table,
      ],
    ],
  ];
  return [
    for (final page in _paginate(blocks)) await _draw(page, width),
  ];
}
