import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:share_plus/share_plus.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/core/platform/image_saver.dart';
import 'package:simsplit/domain/entities/split_report.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/providers/expense_providers.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/share/split_file_name.dart';
import 'package:simsplit/presentation/share/split_image.dart';
import 'package:simsplit/presentation/share/split_text.dart';
import 'package:simsplit/presentation/utils/tracking.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';

typedef NamedImage = ({String name, Uint8List bytes});

/// Saves images to the photo library (or downloads them on the web); a
/// provider so tests can stand in for the device.
final splitImageSaverProvider =
    Provider<Future<ImageSaveResult> Function(List<NamedImage>)>(
        (ref) => saveImages);

/// Hands images to the system share sheet; a provider so tests can stand in.
final splitImageSharerProvider =
    Provider<Future<void> Function(String subject, List<NamedImage>)>(
  (ref) => (subject, images) => SharePlus.instance.share(ShareParams(
        subject: subject,
        files: [
          for (final image in images)
            XFile.fromData(image.bytes,
                mimeType: 'image/png', name: image.name),
        ],
      )),
);

/// The split as it will be sent (#115): the exact images, drawn once when the
/// screen opens, one per page to swipe through (summary, who pays whom,
/// expenses). Tap an image to zoom. Save keeps them; Share sends them.
class ShareSplitPreviewScreen extends ConsumerStatefulWidget {
  const ShareSplitPreviewScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<ShareSplitPreviewScreen> createState() =>
      _ShareSplitPreviewScreenState();
}

typedef _Split = ({
  String title,
  List<SplitImagePart> parts,
  List<String> names,
});

class _ShareSplitPreviewScreenState
    extends ConsumerState<ShareSplitPreviewScreen> {
  Future<_Split>? _split;
  final _pages = PageController();
  int _page = 0;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Drawn once, with the data as it is when the screen opens.
    _split ??= _draw(AppLocalizations.of(context)!);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
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
      final parts = await renderSplitImages(report, l10n);
      final at = DateTime.now();
      return (
        title: splitTitle(report),
        parts: parts,
        names: [
          for (var i = 0; i < parts.length; i++)
            splitFileName(group.name, at, part: i + 1, parts: parts.length),
        ],
      );
    } finally {
      for (final sub in subs) {
        sub.close();
      }
    }
  }

  List<NamedImage> _images(_Split split) => [
        for (final (i, part) in split.parts.indexed)
          (name: split.names[i], bytes: part.png),
      ];

  Future<void> _share(_Split split) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      // A device action, not a use case; the Share tap is the tracked event.
      final share = ref.read(splitImageSharerProvider);
      await share(split.title, _images(split));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.shareSplitFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(_Split split) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final open =
        context.trackedCall(TelemetryEvent.tapOpenSavedImages, openSavedImages);
    setState(() => _busy = true);
    // A device action, not a use case; the Save tap is the tracked event.
    final save = ref.read(splitImageSaverProvider);
    final result = await save(_images(split));
    if (mounted) setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(switch (result) {
        ImageSaveResult.saved =>
          kIsWeb ? l10n.splitImageDownloaded : l10n.splitImageSaved,
        ImageSaveResult.denied => l10n.splitImageSaveDenied,
        ImageSaveResult.failed => l10n.splitImageSaveFailed,
      }),
      action: result == ImageSaveResult.saved && !kIsWeb
          ? SnackBarAction(label: l10n.open, onPressed: open)
          : null,
    ));
  }

  void _zoom(SplitImagePart part) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _ZoomedImage(part: part),
        ),
      );

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
          final count = split.parts.length;
          return Column(
            children: [
              // Which image this is, and dots to show there are more.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.shareSplitPage(
                            _page + 1, count, split.parts[_page].label),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    for (var i = 0; i < count; i++)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _page
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: count,
                  onPageChanged: context.trackedValue(
                      TelemetryEvent.gestureSwipeSplitImage,
                      (int page) => setState(() => _page = page)),
                  itemBuilder: (context, i) => SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: GestureDetector(
                      onTap: context.tracked(TelemetryEvent.tapZoomSplitImage,
                          () => _zoom(split.parts[i])),
                      child: Image.memory(
                        split.parts[i].png,
                        fit: BoxFit.fitWidth,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                        semanticLabel: split.parts[i].label,
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: context.tracked(
                              TelemetryEvent.tapSaveSplitImage,
                              _busy ? null : () => _save(split)),
                          icon: const Icon(Icons.download_rounded),
                          label: Text(l10n.splitImageSave),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: context.tracked(
                              TelemetryEvent.tapShareSplitImage,
                              _busy ? null : () => _share(split)),
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.ios_share_rounded),
                          label: Text(l10n.shareSplitShare),
                        ),
                      ),
                    ],
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

/// One image full screen, to pinch and pan.
class _ZoomedImage extends StatelessWidget {
  const _ZoomedImage({required this.part});

  final SplitImagePart part;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(part.label),
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 6,
        child: Center(
          child: Image.memory(part.png, filterQuality: FilterQuality.medium),
        ),
      ),
    );
  }
}
