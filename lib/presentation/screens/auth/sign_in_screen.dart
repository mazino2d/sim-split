import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/presentation/notifiers/auth_notifier.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';

/// The only screen before the group list (R-3 AC1): the app name, one line
/// on why, and the provider buttons. The router leaves it on its own once
/// the user is signed in.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _failure = null);
    final result = await ref.read(authProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    result.fold(
      (failure) {
        // Closing Google's sheet is a choice, not an error.
        if (failure is! AuthCancelled) setState(() => _failure = failure);
      },
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final busy = ref.watch(authProvider).isLoading;
    final failure = _failure;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(l10n.appTitle, style: theme.textTheme.displaySmall),
              const SizedBox(height: 12),
              Text(
                l10n.signInTagline,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (failure != null) ...[
                Text(
                  failure is AuthNoConnection
                      ? l10n.signInNeedsConnection
                      : l10n.signInFailed,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _GoogleButton(
                label: l10n.continueWithGoogle,
                busy: busy,
                onPressed: busy ? null : _signInWithGoogle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Google's neutral sign-in button: the standard "G" mark on the theme's
/// surface with an outline, as the Google branding guidelines allow.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Image.asset(
              'assets/icons/google_g.png',
              width: 20,
              height: 20,
              excludeFromSemantics: true,
            ),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}
