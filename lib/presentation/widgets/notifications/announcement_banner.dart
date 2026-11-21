import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/notifications/announcement.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/notifiers/notification_notifier.dart';
import 'package:simsplit/presentation/providers/notification_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

/// A notice from the maintainer at the top of the home screen (R-9 AC12):
/// one at a time, inline, in the app's language, until dismissed on any of
/// the account's devices or until it ends. Tapping it shows the whole text.
class AnnouncementBanner extends ConsumerStatefulWidget {
  const AnnouncementBanner({super.key});

  @override
  ConsumerState<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends ConsumerState<AnnouncementBanner> {
  // Recorded once per banner per app run.
  final _shown = <String>{};
  // Hidden at once on dismiss, before the account's list syncs back.
  final _dismissed = <String>{};
  bool _expanded = false;

  void _recordShown(Announcement announcement, String result) {
    if (!_shown.add(announcement.id)) return;
    final event = TelemetryEvent.opAnnouncementShown;
    try {
      ref.read(trackEventProvider)(event.kind, event.wireName, result: result);
    } on Object {
      // Telemetry never gets in the user's way.
    }
  }

  @override
  Widget build(BuildContext context) {
    final announcement = ref.watch(currentAnnouncementProvider).value;
    // Keeps the notifier alive while a dismissal saves.
    ref.watch(notificationProvider);
    if (announcement == null || _dismissed.contains(announcement.id)) {
      return const SizedBox.shrink();
    }
    final language = Localizations.localeOf(context).languageCode;
    final copy = announcement.copyFor(language);
    final result = configIdResult('campaign', announcement.id);
    if (copy == null || result == null) return const SizedBox.shrink();
    _recordShown(announcement, result);

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppTheme.gutter, 4, AppTheme.gutter, 8),
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          onTap: context.trackedWith(TelemetryEvent.tapAnnouncement, result,
              () => setState(() => _expanded = !_expanded)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.campaign_outlined,
                      size: 20, color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(copy.title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        copy.body,
                        maxLines: _expanded ? null : 2,
                        overflow: _expanded ? null : TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: l10n.dismissAnnouncement,
                  onPressed: context.trackedWith(
                      TelemetryEvent.tapDismissAnnouncement, result, () {
                    setState(() => _dismissed.add(announcement.id));
                    ref
                        .read(notificationProvider.notifier)
                        .dismissAnnouncement(announcement.id);
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
