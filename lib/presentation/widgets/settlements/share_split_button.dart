import 'package:flutter/material.dart';
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

/// The floating "Share the split" button on the Settlements tab (#115,
/// UC-5.1). It draws the whole split as one image on the device and hands
/// it to the share sheet the user picks.
class ShareSplitButton extends ConsumerStatefulWidget {
  const ShareSplitButton({super.key, required this.group, this.enabled = true});

  final Group group;
  final bool enabled;

  @override
  ConsumerState<ShareSplitButton> createState() => _ShareSplitButtonState();
}

class _ShareSplitButtonState extends ConsumerState<ShareSplitButton> {
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

  Future<void> _share() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final report = await _report();
      final images = await renderSplitImages(report, l10n);
      await SharePlus.instance.share(ShareParams(
        subject: splitTitle(report, l10n),
        files: [
          for (final (i, png) in images.indexed)
            XFile.fromData(png,
                mimeType: 'image/png',
                name: images.length == 1
                    ? 'simsplit.png'
                    : 'simsplit-${i + 1}.png'),
        ],
      ));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.shareSplitFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FloatingActionButton.extended(
      heroTag: 'shareSplit',
      onPressed: context.tracked(TelemetryEvent.tapShareSplit,
          widget.enabled && !_busy ? _share : null),
      icon: _busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.ios_share_rounded),
      label: Text(l10n.shareSplit),
    );
  }
}
