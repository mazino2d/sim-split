import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:simsplit/core/constants/app_links.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/failures/auth_failure.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/presentation/notifiers/auth_notifier.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

/// The only screen before the group list (R-3 AC1): the app name, one line
/// on why, and the Google button (Sign in with Apple joins in R-3 P8). The router leaves it on its own once
/// the user is signed in. Signing in is agreeing to the privacy policy, said
/// in one line under the button; the details are in the policy (R-4 AC6).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  Failure? _failure;
  late final _policyTap = TapGestureRecognizer()
    ..onTap = () {
      context.track(TelemetryEvent.tapPrivacyPolicy);
      launchUrl(privacyPolicyUrl, mode: LaunchMode.externalApplication);
    };

  @override
  void dispose() {
    _policyTap.dispose();
    super.dispose();
  }

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
                onPressed: context.tracked(TelemetryEvent.tapSignInGoogle,
                    busy ? null : _signInWithGoogle),
              ),
              const SizedBox(height: 16),
              Text.rich(
                TextSpan(
                  text: l10n.signInAgreementPrefix,
                  children: [
                    TextSpan(
                      text: l10n.privacyPolicyLink,
                      recognizer: _policyTap,
                      style:
                          const TextStyle(decoration: TextDecoration.underline),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
