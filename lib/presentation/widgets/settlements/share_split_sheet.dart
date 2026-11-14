import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/split_report.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/share/split_image.dart';
import 'package:simsplit/presentation/share/split_text.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

/// Opens the choice of sending the group's split as images or as text
/// (#115, UC-5.1). Everything is made on the device and leaves it only
/// through the share sheet the user picks.
Future<void> showShareSplitSheet(BuildContext context, Group group) =>
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ShareSplitSheet(group: group),
    );

class ShareSplitSheet extends ConsumerStatefulWidget {
  const ShareSplitSheet({super.key, required this.group});

  final Group group;

  @override
  ConsumerState<ShareSplitSheet> createState() => _ShareSplitSheetState();
}

class _ShareSplitSheetState extends ConsumerState<ShareSplitSheet> {
  bool _busy = false;

  Future<SplitReport> _report() async {
    final group = widget.group;
    const wait = Duration(seconds: 10);
    final summary = await ref
        .read(debtSummaryProvider(group.id, group.currencyCode).future)
        .timeout(wait);
    final expenses =
        await ref.read(expenseListProvider(group.id).future).timeout(wait);
    return buildSplitReport(group: group, expenses: expenses, summary: summary);
  }

  Future<void> _share({required bool asImage}) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final report = await _report();
      final text = splitReportText(report, l10n);
      if (!asImage && kIsWeb) {
        // Browsers rarely share plain text: copy it instead.
        await Clipboard.setData(ClipboardData(text: text));
        messenger.showSnackBar(SnackBar(content: Text(l10n.copied)));
      } else if (!asImage) {
        await SharePlus.instance
            .share(ShareParams(text: text, subject: splitTitle(report, l10n)));
      } else {
        final images = await renderSplitImages(report, l10n);
        await SharePlus.instance.share(ShareParams(
          subject: splitTitle(report, l10n),
          files: [
            for (final (i, png) in images.indexed)
              XFile.fromData(png,
                  mimeType: 'image/png', name: 'simsplit-${i + 1}.png'),
          ],
        ));
      }
      navigator.pop();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.shareSplitFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(l10n.shareSplit, style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l10n.shareSplitHint,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            if (_busy) const LinearProgressIndicator(),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(l10n.shareAsImage),
              enabled: !_busy,
              onTap: context.tracked(TelemetryEvent.tapShareSplitImage,
                  () => _share(asImage: true)),
            ),
            ListTile(
              leading: const Icon(Icons.notes_rounded),
              title: Text(l10n.shareAsText),
              enabled: !_busy,
              onTap: context.tracked(TelemetryEvent.tapShareSplitText,
                  () => _share(asImage: false)),
            ),
          ],
        ),
      ),
    );
  }
}
