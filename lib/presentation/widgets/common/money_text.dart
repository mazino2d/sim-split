import 'package:flutter/material.dart';

import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';

/// An amount in tabular figures.
///
/// With [signed], positive amounts get a `+`, negative a `−`, and both are
/// coloured with the theme's money colours.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amountCents,
    this.currencyCode, {
    super.key,
    this.style,
    this.signed = false,
    this.color,
    this.textAlign,
  });

  final int amountCents;
  final String currencyCode;
  final TextStyle? style;
  final bool signed;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final formatted = formatMoney(amountCents.abs(), currencyCode);
    final prefix = !signed || amountCents == 0
        ? (amountCents < 0 ? '−' : '')
        : (amountCents > 0 ? '+' : '−');
    final resolvedColor =
        color ?? (signed ? context.money.forSign(amountCents, cs) : null);
    return Text(
      '$prefix$formatted',
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: (style ?? DefaultTextStyle.of(context).style).copyWith(
        color: resolvedColor,
        fontFeatures: tabularFigures,
      ),
    );
  }
}
