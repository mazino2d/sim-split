import 'package:flutter/material.dart';

import 'package:simsplit/presentation/theme/app_theme.dart';

/// Small muted heading that introduces a block of content, with an optional
/// trailing widget (e.g. a total).
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppTheme.gutter,
      24,
      AppTheme.gutter,
      8,
    ),
  });

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(text, style: style)),
          if (trailing != null)
            DefaultTextStyle.merge(style: style, child: trailing!),
        ],
      ),
    );
  }
}
