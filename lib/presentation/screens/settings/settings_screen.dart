import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/presentation/providers/locale_provider.dart';
import 'package:simsplit/presentation/providers/theme_mode_provider.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/widgets/common/section_label.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currentLocale =
        ref.watch(localeProvider).value ?? deviceDefaultLocale();
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    Widget block(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
          child: SizedBox(width: double.infinity, child: child),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          SectionLabel(l10n.language),
          block(
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'vi', label: Text(l10n.vietnamese)),
                ButtonSegment(value: 'en', label: Text(l10n.english)),
              ],
              selected: {currentLocale.languageCode},
              onSelectionChanged: (selected) => ref
                  .read(localeProvider.notifier)
                  .setLocale(Locale(selected.first)),
            ),
          ),
          SectionLabel(l10n.appearance),
          block(
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: ThemeMode.system, label: Text(l10n.themeSystem)),
                ButtonSegment(
                    value: ThemeMode.light, label: Text(l10n.themeLight)),
                ButtonSegment(
                    value: ThemeMode.dark, label: Text(l10n.themeDark)),
              ],
              selected: {themeMode},
              onSelectionChanged: (selected) => ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(selected.first),
            ),
          ),
        ],
      ),
    );
  }
}
