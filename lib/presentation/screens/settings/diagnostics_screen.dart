import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:simsplit/core/constants/app_links.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/presentation/notifiers/error_reports_notifier.dart';
import 'package:simsplit/presentation/providers/telemetry_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

/// Debug details kept out of the main Settings list (R-4 AC25–AC27): the
/// error report switch, the report ID testers quote, the app version and
/// platform, and how many reports wait to be sent. Opened from the wrench
/// in the Settings app bar.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = ref.watch(errorReportSettingsProvider).value;
    // Keep the notifier alive while the switch saves.
    final busy = ref.watch(errorReportsProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.diagnostics)),
      body: settings == null
          ? const SizedBox.shrink()
          : ListView(
              children: [
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
                  title: Text(l10n.errorReportsSwitch),
                  subtitle: Text(l10n.errorReportsExplanation),
                  value: settings.enabled,
                  onChanged: context.trackedValue(
                      TelemetryEvent.tapErrorReportsSwitch,
                      busy
                          ? null
                          : (on) => ref
                              .read(errorReportsProvider.notifier)
                              .setEnabled(on)),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: context.tracked(
                          TelemetryEvent.tapPrivacyPolicy,
                          () => launchUrl(privacyPolicyUrl,
                              mode: LaunchMode.externalApplication)),
                      child: Text(l10n.privacyPolicy),
                    ),
                  ),
                ),
                if (settings.reportId case final reportId?)
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
                    title: Text(l10n.reportIdLabel),
                    subtitle: Text(l10n.reportIdHint),
                    trailing: Semantics(
                      // Read out character by character (AC27).
                      label: reportId.split('').join(' '),
                      excludeSemantics: true,
                      child: SelectableText(
                        reportId,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    onTap: context.tracked(TelemetryEvent.tapCopyReportId,
                        () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: reportId));
                      messenger
                          .showSnackBar(SnackBar(content: Text(l10n.copied)));
                    }),
                  ),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
                  title: Text(l10n.appVersionLabel),
                  trailing: Text(settings.appVersion),
                ),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
                  title: Text(l10n.platformLabel),
                  trailing: Text(settings.platform),
                ),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
                  title: Text(l10n.errorReportsWaiting),
                  trailing: Text('${settings.waitingCount}'),
                ),
              ],
            ),
    );
  }
}
