import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'locale_provider.g.dart';

/// Language codes the app ships translations for.
const supportedLanguageCodes = {'en', 'vi'};

/// The device's preferred language if supported, otherwise English.
Locale deviceDefaultLocale() {
  final device = WidgetsBinding.instance.platformDispatcher.locale;
  return supportedLanguageCodes.contains(device.languageCode)
      ? Locale(device.languageCode)
      : const Locale('en');
}

@riverpod
class LocaleNotifier extends _$LocaleNotifier {
  static const _key = 'locale_language_code';

  @override
  Future<Locale> build() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    if (code != null && supportedLanguageCodes.contains(code)) {
      return Locale(code);
    }
    return deviceDefaultLocale();
  }

  Future<void> setLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.languageCode);
    if (ref.mounted) state = AsyncData(locale);
  }
}
