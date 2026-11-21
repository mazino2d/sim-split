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
// leaves it until the user shares or saves. The summary comes first, then
// who pays whom, then every expense.
//
// Amounts never wrap: each number column is as wide as its longest amount.
// Names and titles take the rest of the width and wrap. Every table spans
// the full width of the image.
//
// Up to [_maxMemberColumns] members, the expenses are a table with one
// column per member. Bigger groups get a list instead, so the image stays
// phone width. An image stops at [_maxImageHeight] or [_maxImagePixels],
// whichever comes first, and the rest continues in another image: phones
// cannot draw an image of any size.

const _maxImageHeight = 12000.0;
const _maxImagePixels = 16000000.0;
const _minWidth = 1080.0;
const _minFlexWidth = 340.0;
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

const _bodySize = 28.0;
const _headerSize = 24.0;
const _subSize = 22.0;

class _Cell {
  const _Cell(this.text,
      {this.sub, this.bold = false, this.color, this.background});

  final String text;
  final String? sub;
  final bool bold;
  final Color? color;

  /// Fills this cell only, for the "send to" column.
  final Color? background;
}

class _Row {
  const _Row(this.cells, {this.background, this.bold = false});

  final List<_Cell> cells;
  final Color? background;
  final bool bold;
}

/// A table column: numbers sit right and never wrap; a flexible column takes
/// what is left of the width and wraps.
class _Col {
  const _Col({this.numeric = false, this.flex = false});

  final bool numeric;
  final bool flex;
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

double _textWidth(String text, TextStyle style) =>
    _layout(text, style, double.infinity).width;

/// The widest word of [text]: a header may wrap between words, not inside.
double _longestWord(String text, TextStyle style) => text
    .split(RegExp(r'\s+'))
    .map((w) => _textWidth(w, style))
    .fold(0.0, math.max);

/// A table before it is laid out to the image's width.
class _TableSpec {
  _TableSpec(this.cols, this.header, this.rows);

  final List<_Col> cols;
  final List<String> header;
  final List<_Row> rows;

  /// Each fixed column's width: its widest amount, or its header's widest
  /// word, plus padding. Flexible columns are 0 here.
  late final List<double> fixed = [
    for (var i = 0; i < cols.length; i++)
      cols[i].flex
          ? 0
          : [
                _longestWord(header[i], _style(_headerSize, bold: true)),
                for (final r in rows)
                  if (i < r.cells.length) ...[
                    _textWidth(r.cells[i].text, _style(_bodySize, bold: true)),
                    if (r.cells[i].sub case final sub?)
                      _textWidth(sub, _style(_subSize)),
                  ],
              ].fold(0.0, math.max) +
              _cellPad * 2,
  ];

  int get flexCount => cols.where((c) => c.flex).length;

  /// The narrowest width this table fits in without wrapping an amount.
  double get minWidth =>
      fixed.fold(0.0, (a, b) => a + b) + flexCount * _minFlexWidth;

  /// The widest text of each flexible column on one line, plus padding: it
  /// never needs more than this.
  late final List<double> _natural = [
    for (var i = 0; i < cols.length; i++)
      !cols[i].flex
          ? 0
          : [
                for (final r in rows)
                  if (i < r.cells.length) ...[
                    _textWidth(r.cells[i].text, _style(_bodySize, bold: true)),
                    if (r.cells[i].sub case final sub?)
                      _textWidth(sub, _style(_subSize)),
                  ],
              ].fold(_minFlexWidth - _cellPad * 2, math.max) +
              _cellPad * 2,
  ];

  /// Lays the table out to [width]: flexible columns grow up to their text,
  /// then any width left is spread over every column, so a short table
  /// still spans the image without a wide gap in one place.
  List<_RowBlock> layout(double width) {
    final rest = width - fixed.fold(0.0, (a, b) => a + b);
    final want = _natural.fold(0.0, (a, b) => a + b);
    final widths = [
      for (var i = 0; i < cols.length; i++)
        cols[i].flex
            ? (rest >= want
                ? _natural[i]
                : math.max(_minFlexWidth, rest * _natural[i] / want))
            : fixed[i],
    ];
    final slack = width - widths.fold(0.0, (a, b) => a + b);
    if (slack > 0) {
      for (var i = 0; i < widths.length; i++) {
        widths[i] += slack / widths.length;
      }
    }
    final numeric = [for (final c in cols) c.numeric];
    final head = _RowBlock(
        widths, numeric, _Row([for (final h in header) _Cell(h)]),
        background: _headerBg,
        ink: _headerInk,
        size: _headerSize,
        minHeight: 64);
    return [
      head,
      for (final (i, row) in rows.indexed)
        _RowBlock(widths, numeric, row,
            background: row.background ?? (i.isOdd ? _zebra : _paper),
            header: head),
    ];
  }
}

/// A piece of the image, drawn top to bottom.
abstract class _Block {
  double get height;
  void paint(Canvas canvas, double y);
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

/// Coloured squares that say what the colours of a column mean.
class _LegendBlock implements _Block {
  _LegendBlock(List<(Color, String)> items, double width)
      : _items = [
          for (final (color, text) in items)
            (color, _layout(text, _style(26), width - 40)),
        ];

  final List<(Color, TextPainter)> _items;

  @override
  double get height => 16 + _items.fold(0.0, (sum, i) => sum + i.$2.height + 8);

  @override
  void paint(Canvas canvas, double y) {
    var top = y + 16;
    for (final (color, painter) in _items) {
      final square = painter.height / 2 - 11;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(_margin, top + square, 22, 22),
              const Radius.circular(4)),
          Paint()..color = color);
      painter.paint(canvas, Offset(_margin + 36, top));
      top += painter.height + 8;
    }
  }
}

/// One table row; its height follows its tallest cell.
class _RowBlock implements _Block {
  _RowBlock(
    this.widths,
    this.numeric,
    this._row, {
    required Color background,
    Color ink = _ink,
    double size = _bodySize,
    double minHeight = 60,
    this.header,
  }) : _background = background {
    for (var i = 0; i < _row.cells.length; i++) {
      final cell = _row.cells[i];
      final w = widths[i] - _cellPad * 2;
      final align = numeric[i] ? TextAlign.right : TextAlign.left;
      _main.add(_layout(
          cell.text,
          _style(size, bold: _row.bold || cell.bold, color: cell.color ?? ink),
          w,
          align: align));
      _sub.add(cell.sub == null
          ? null
          : _layout(cell.sub!, _style(_subSize, color: _muted), w,
              align: align));
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
  final _Row _row;

  /// The table's header row, repeated when the table continues in the next
  /// image; null for the header itself.
  final _RowBlock? header;
  final Color _background;
  final _main = <TextPainter>[];
  final _sub = <TextPainter?>[];

  @override
  late final double height;

  double get width => widths.fold(0.0, (a, b) => a + b);

  @override
  void paint(Canvas canvas, double y) {
    canvas.drawRect(
        Rect.fromLTWH(_margin, y, width, height), Paint()..color = _background);
    var x = _margin;
    for (var i = 0; i < _main.length; i++) {
      if (_row.cells[i].background case final color?) {
        canvas.drawRect(
            Rect.fromLTWH(x, y, widths[i], height), Paint()..color = color);
      }
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

/// The summary: each member's share, what they paid, what they settled, and
/// what they send to (or get back from) the collector, or their net.
_TableSpec _summaryTable(SplitReport r, AppLocalizations l10n) {
  final currency = r.group.currencyCode;
  String money(int cents) => shareMoney(cents, currency);
  final collector = r.mode == SettlementMode.hub ? r.collector : null;
  final settled = r.balances.any((b) => b.settledCents != 0);

  _Row memberRow(int i) {
    final b = r.balances[i];
    final isCollector = b.member.id == collector?.id;
    final last = collector == null ? b.netAmountCents : r.toCollector(b.member);
    final _Cell lastCell;
    if (collector == null) {
      // Green: gets money back; red: still pays.
      lastCell = _Cell(last == 0 ? '–' : money(last.abs()),
          bold: true, color: last > 0 ? _getBack : (last < 0 ? _pay : _ink));
    } else if (isCollector) {
      lastCell = _Cell(l10n.splitCollector, color: _muted);
    } else {
      // Red: sends to the collector; green: the collector sends it back.
      lastCell = _Cell(last == 0 ? '–' : money(last.abs()),
          bold: true,
          color: last > 0 ? _pay : (last < 0 ? _getBack : _ink),
          background: last > 0 ? _payBg : (last < 0 ? _getBackBg : null));
    }
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
    );
  }

  final totalShare = r.balances.fold(0, (s, b) => s + b.shareCents);
  final totalPaid = r.balances.fold(0, (s, b) => s + b.paidCents);
  return _TableSpec(
    [
      const _Col(flex: true),
      const _Col(numeric: true),
      const _Col(numeric: true),
      if (settled) const _Col(numeric: true),
      const _Col(numeric: true),
    ],
    [
      l10n.splitColMember,
      l10n.splitColShare,
      l10n.splitColPaid,
      if (settled) l10n.splitColSettled,
      collector == null
          ? l10n.splitColNet
          : l10n.splitColSendTo(collector.name),
    ],
    [
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
  );
}

/// What the colours of the summary's last column mean.
List<(Color, String)> _legend(SplitReport r, AppLocalizations l10n) {
  final collector = r.mode == SettlementMode.hub ? r.collector : null;
  return collector == null
      ? [
          (_getBack, l10n.splitLegendGetsBack),
          (_pay, l10n.splitLegendStillPays),
        ]
      : [
          (_pay, l10n.splitLegendSendTo(collector.name)),
          (_getBack, l10n.splitLegendSendsBack(collector.name)),
        ];
}

/// Who pays whom: the transfers that settle everyone, in either mode.
_TableSpec? _transfersTable(SplitReport r, AppLocalizations l10n) {
  if (r.transfers.isEmpty) return null;
  final currency = r.group.currencyCode;
  return _TableSpec(
    const [_Col(flex: true), _Col(flex: true), _Col(numeric: true)],
    [l10n.splitColFrom, l10n.splitColTo, l10n.splitColAmount],
    [
      for (final t in r.transfers)
        _Row([
          _Cell(t.from.name),
          _Cell(t.to.name),
          _Cell(shareMoney(t.amountCents, currency), bold: true),
        ]),
    ],
  );
}

/// The expenses as a list: who paid, then "split equally" or each member's
/// part, wrapping in full. It reads the same at any group size.
_TableSpec _expenseList(SplitReport r, AppLocalizations l10n) {
  final currency = r.group.currencyCode;
  String money(int cents) => shareMoney(cents, currency);
  final order = {for (final (i, b) in r.balances.indexed) b.member.id: i};
  final names = {for (final b in r.balances) b.member.id: b.member.name};
  String parts(SplitReportRow row) {
    final shares = row.shares.entries.toList()
      ..sort((a, b) => (order[a.key] ?? 0).compareTo(order[b.key] ?? 0));
    final values = shares.map((e) => e.value);
    // Rounding can leave a cent between equal parts.
    final equal = shares.length > 1 &&
        values.reduce(math.max) - values.reduce(math.min) <= 1;
    return equal
        ? l10n.splitPaidByEqual(
            row.paidBy.name, shares.length, money(shares.first.value))
        : l10n.splitPaidByParts(
            row.paidBy.name,
            shares
                .map((e) => '${names[e.key] ?? '?'} ${money(e.value)}')
                .join(' · '));
  }

  return _TableSpec(
    const [_Col(), _Col(flex: true), _Col(numeric: true)],
    ['#', l10n.splitColExpense, l10n.splitColAmount],
    [
      for (final (i, row) in r.rows.indexed)
        _Row([
          _Cell('${i + 1}', color: _muted),
          _Cell(row.title, sub: parts(row)),
          _Cell(money(row.amountCents)),
        ]),
      _Row([
        const _Cell(''),
        _Cell(l10n.splitRowTotal),
        _Cell(money(r.totalCents)),
      ], background: _totalBg, bold: true),
    ],
  );
}

/// Spreads [blocks] over as few images as fit [maxHeight], repeating a
/// table's header when it continues in the next image.
List<List<_Block>> _paginate(List<_Block> blocks, double maxHeight) {
  final room = maxHeight - _margin * 2 - 48;
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

/// One image of the shared split, and the part of the split it shows.
class SplitImagePart {
  const SplitImagePart({required this.label, required this.png});

  /// "Summary", "Who pays whom" or "Expenses".
  final String label;
  final Uint8List png;
}

/// The split as PNG images, one per part: the summary, who pays whom, and
/// the expenses. Each starts with the group's name and the part's title; a
/// part too big for one image continues in the next.
Future<List<SplitImagePart>> renderSplitImages(
    SplitReport report, AppLocalizations l10n) async {
  final summary = _summaryTable(report, l10n);
  final transfers = _transfersTable(report, l10n);
  final expenses = report.rows.isEmpty ? null : _expenseList(report, l10n);
  final tables = [
    summary,
    if (transfers != null) transfers,
    if (expenses != null) expenses,
  ];
  final inner = math.max(_minWidth - _margin * 2,
      tables.map((t) => t.minWidth).fold(0.0, math.max));
  final width = inner + _margin * 2;
  final currency = report.group.currencyCode;
  final note = report.mode == SettlementMode.hub &&
          report.collector == null &&
          report.balances.any((b) => b.netAmountCents != 0)
      ? l10n.splitNoCollector
      : l10n.splitAllSettled;

  final sections = <(String, List<_Block>)>[
    (
      l10n.splitSectionSummary,
      [...summary.layout(inner), _LegendBlock(_legend(report, l10n), inner)],
    ),
    (
      l10n.whoPaysWhom,
      transfers == null
          ? [_TextBlock(note, _style(28), inner)]
          : transfers.layout(inner),
    ),
    if (expenses != null) (l10n.expenses, expenses.layout(inner)),
  ];

  final maxHeight = math.min(_maxImageHeight, _maxImagePixels / width);
  final parts = <SplitImagePart>[];
  for (final (label, blocks) in sections) {
    final head = <_Block>[
      _TextBlock(splitTitle(report), _style(40, bold: true), inner,
          gapAfter: 6),
      _TextBlock(
          l10n.splitSubtitle(
              shareMoney(report.totalCents, currency), report.rows.length),
          _style(26, color: _muted),
          inner,
          gapAfter: 28),
      _TextBlock(label, _style(36, bold: true), inner, gapAfter: 16),
    ];
    final headHeight = head.fold(0.0, (sum, b) => sum + b.height);
    for (final page in _paginate(blocks, maxHeight - headHeight)) {
      parts.add(SplitImagePart(
          label: label, png: await _draw([...head, ...page], width)));
    }
  }
  return parts;
}
