import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simsplit/core/l10n/generated/app_localizations_en.dart';
import 'package:simsplit/presentation/utils/relative_time.dart';

void main() {
  final l10n = AppLocalizationsEn();
  final now = DateTime(2026, 10, 6, 12);

  setUpAll(() => initializeDateFormatting('en'));

  String ago(Duration d) => relativeTime(now.subtract(d), l10n, 'en', now: now);

  test('says just now under a minute', () {
    expect(ago(const Duration(seconds: 30)), 'just now');
  });

  test('counts minutes under an hour and hours under a day', () {
    expect(ago(const Duration(minutes: 5)), '5 min ago');
    expect(ago(const Duration(hours: 3, minutes: 20)), '3 h ago');
  });

  test('shows the date after a day', () {
    expect(ago(const Duration(days: 2)), '4 Oct 2026');
  });
}
