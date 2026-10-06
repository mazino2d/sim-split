import 'package:flutter/material.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';

/// The subtle "not synced yet" mark on a record whose change has not
/// reached the cloud (R-3 AC16). It goes away on its own once pushed.
class UnsyncedMark extends StatelessWidget {
  const UnsyncedMark({super.key});

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context)!.notSyncedYet;
    return Tooltip(
      message: label,
      child: Icon(
        Icons.cloud_upload_outlined,
        size: 14,
        semanticLabel: label,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
