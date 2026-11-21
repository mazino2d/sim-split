import 'package:intl/intl.dart';

const _from =
    'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
const _to =
    'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// The group's name for a file: Vietnamese marks removed, lower case, words
/// joined by "-", at most [maxLength] characters.
String fileSlug(String name, {int maxLength = 40}) {
  final plain = StringBuffer();
  // Marks typed as separate characters (decomposed text) go first.
  final base = name.toLowerCase().replaceAll(RegExp('[\u0300-\u036f]'), '');
  for (final ch in base.split('')) {
    final i = _from.indexOf(ch);
    plain.write(i < 0 ? ch : _to[i]);
  }
  var slug = plain
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > maxLength) {
    slug = slug.substring(0, maxLength).replaceAll(RegExp(r'-+$'), '');
  }
  return slug;
}

/// `simsplit-<group>-<yyyyMMdd>-<HHmm>.png`, with "-1", "-2"… when the split
/// is in more than one image.
String splitFileName(String groupName, DateTime at,
    {int part = 1, int parts = 1}) {
  final slug = fileSlug(groupName);
  final time = DateFormat('yyyyMMdd-HHmm').format(at);
  final stem = [
    'simsplit',
    if (slug.isNotEmpty) slug,
    time,
    if (parts > 1) '$part',
  ].join('-');
  return '$stem.png';
}
