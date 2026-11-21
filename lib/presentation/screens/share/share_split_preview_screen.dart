import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:share_plus/share_plus.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/split_report.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/share/split_image.dart';
import 'package:simsplit/presentation/share/split_text.dart';
import 'package:simsplit/presentation/utils/tracking.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';

/// The split as it will be sent (#115): the exact images, drawn once when the
/// screen opens, to scroll and zoom through before tapping Share.
class ShareSplitPreviewScreen extends ConsumerStatefulWidget {
  const ShareSplitPreviewScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<ShareSplitPreviewScreen> createState() =>
      _ShareSplitPreviewScreenState();
}

typedef _Split = ({String title, List<Uint8List> images});

class _ShareSplitPreviewScreenState
    extends ConsumerState<ShareSplitPreviewScreen> {
  Future<_Split>? _split;
  bool _sharing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Drawn once, with the data as it is when the screen opens.
    _split ??= _draw(AppLocalizations.of(context)!);
  }

  Future<_Split> _draw(AppLocalizations l10n) async {
    const wait = Duration(seconds: 10);
    // Listening keeps the auto-dispose providers alive until they load,
    // even when this screen is opened directly by its URL.
    final subs = <ProviderSubscription<Object?>>[];
    void keep(ProviderListenable<Object?> provider) =>
        subs.add(ref.listenManual(provider, (_, __) {}));
    try {
      keep(groupDetailProvider(widget.groupId));
      final group = await ref
          .read(groupDetailProvider(widget.groupId).future)
          .timeout(wait);
      keep(debtSummaryProvider(group.id, group.currencyCode));
      keep(expenseListProvider(group.id));
      final summary = await ref
          .read(debtSummaryProvider(group.id, group.currencyCode).future)
          .timeout(wait);
      final expenses =
          await ref.read(expenseListProvider(group.id).future).timeout(wait);
      final report =
          buildSplitReport(group: group, expenses: expenses, summary: summary);
      return (
        title: splitTitle(report, l10n),
        images: await renderSplitImages(report, l10n),
      );
    } finally {
      for (final sub in subs) {
        sub.close();
      }
    }
  }

  Future<void> _share(_Split split) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sharing = true);
    try {
      await SharePlus.instance.share(ShareParams(
        subject: split.title,
        files: [
          for (final (i, png) in split.images.indexed)
            XFile.fromData(png,
                mimeType: 'image/png',
                name: split.images.length == 1
                    ? 'simsplit.png'
                    : 'simsplit-${i + 1}.png'),
        ],
      ));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.shareSplitFailed)));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shareSplit)),
      body: FutureBuilder<_Split>(
        future: _split,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.shareSplitFailed, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: context.tracked(TelemetryEvent.tapRetry,
                          () => setState(() => _split = _draw(l10n))),
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            );
          }
          final split = snapshot.data;
          if (split == null) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const AppLoadingWidget(),
                Text(l10n.shareSplitPreparing,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            );
          }
          return Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => InteractiveViewer(
                    constrained: false,
                    minScale: 1,
                    maxScale: 5,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: Column(
                        children: [
                          for (final (i, png) in split.images.indexed) ...[
                            if (split.images.length > 1)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    l10n.shareSplitPart(
                                        i + 1, split.images.length),
                                    style: theme.textTheme.labelLarge,
                                  ),
                                ),
                              ),
                            Image.memory(
                              png,
                              width: constraints.maxWidth,
                              fit: BoxFit.fitWidth,
                              filterQuality: FilterQuality.medium,
                              gaplessPlayback: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: context.tracked(
                          TelemetryEvent.tapShareSplitImage,
                          _sharing ? null : () => _share(split)),
                      icon: _sharing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share_rounded),
                      label: Text(l10n.shareSplitShare),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
