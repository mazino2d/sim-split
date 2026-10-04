import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fpdart/fpdart.dart' show Either, Unit;

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/presentation/notifiers/auth_notifier.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/presentation/providers/locale_provider.dart';
import 'package:simsplit/presentation/providers/theme_mode_provider.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';
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
          if (ref.watch(authAvailableProvider)) const _AccountSection(),
        ],
      ),
    );
  }
}

/// Who is signed in, with sign-out and account deletion (R-3 AC5, AC6).
/// Both actions remove the account's data from this phone, so both are
/// confirmed. The router returns to sign-in once the session ends.
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  Future<void> _confirmAndRun(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String message,
    required String action,
    required Future<Either<Failure, Unit>> Function(AuthNotifier) run,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dCtx).colorScheme.error,
              foregroundColor: Theme.of(dCtx).colorScheme.onError,
              minimumSize: const Size(64, 44),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await run(ref.read(authProvider.notifier));
    result.fold(
      (failure) {
        if (failure is AuthCancelled) return;
        messenger.showSnackBar(
          SnackBar(content: Text(failureMessage(failure, l10n))),
        );
      },
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider).value;
    // Keep the notifier alive while an action runs.
    final busy = ref.watch(authProvider).isLoading;
    if (user == null) return const SizedBox.shrink();

    final name = user.displayName ?? user.email ?? '';
    final email = user.displayName == null ? null : user.email;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(l10n.account),
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
          title: Text(name),
          subtitle: email == null ? null : Text(email),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
          child: OutlinedButton(
            onPressed: busy
                ? null
                : () => _confirmAndRun(
                      context,
                      ref,
                      title: l10n.signOutConfirmTitle,
                      message: l10n.signOutConfirmMessage,
                      action: l10n.signOut,
                      run: (n) => n.signOut(),
                    ),
            child: Text(l10n.signOut),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.gutter, 8, AppTheme.gutter, AppTheme.gutter),
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: busy
                ? null
                : () => _confirmAndRun(
                      context,
                      ref,
                      title: l10n.deleteAccountConfirmTitle,
                      message: l10n.deleteAccountConfirmMessage,
                      action: l10n.delete,
                      run: (n) => n.deleteAccount(),
                    ),
            child: Text(l10n.deleteAccount),
          ),
        ),
      ],
    );
  }
}
