import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

/// The floating "Share the split" button on the Settlements tab (#115,
/// UC-5.1). It opens the preview of the image, where Share sends it.
class ShareSplitButton extends StatelessWidget {
  const ShareSplitButton({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FloatingActionButton.extended(
      heroTag: 'shareSplit',
      onPressed: context.tracked(TelemetryEvent.tapShareSplit,
          () => context.push('/groups/${group.id}/share')),
      icon: const Icon(Icons.ios_share_rounded),
      label: Text(l10n.shareSplit),
    );
  }
}
