import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/presentation/providers/locale_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final localeAsync = ref.watch(localeNotifierProvider);
    final currentLocale = localeAsync.valueOrNull ?? const Locale('vi');

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text(l10n.language),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'vi', label: Text(l10n.vietnamese)),
                  ButtonSegment(value: 'en', label: Text(l10n.english)),
                ],
                selected: {currentLocale.languageCode},
                onSelectionChanged: (selected) {
                  ref
                      .read(localeNotifierProvider.notifier)
                      .setLocale(Locale(selected.first));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
