import 'package:simsplit/core/utils/money_formatter.dart';
import 'package:simsplit/domain/entities/split_report.dart';

/// Money in shared output: "đ" rather than "₫", which common chat fonts
/// render too small (#115).
String shareMoney(int cents, String currencyCode) =>
    formatMoney(cents, currencyCode).replaceAll('₫', 'đ');

/// The group's name with its emoji: the title of the shared split.
String splitTitle(SplitReport r) =>
    '${r.group.emoji ?? ''} ${r.group.name}'.trim();
