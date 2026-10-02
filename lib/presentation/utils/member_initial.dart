import 'package:flutter/widgets.dart';

/// First user-perceived character (grapheme cluster) of [name], upper-cased,
/// for avatar placeholders. Safe for emoji/combining characters and empty
/// names (returns `?`).
String nameInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}
