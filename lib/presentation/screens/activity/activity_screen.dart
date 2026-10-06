import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/activity_entry.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/utils/activity_text.dart';
import 'package:simsplit/presentation/utils/relative_time.dart';
import 'package:simsplit/presentation/widgets/common/empty_state.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';
import 'package:simsplit/presentation/widgets/common/section_label.dart';
import 'package:simsplit/presentation/widgets/common/unsynced_mark.dart';

/// Reads a group's history and members into an [ActivityText], or null
/// while they load.
ActivityText? _activityText(
    BuildContext context, WidgetRef ref, String groupId) {
  final entries = ref.watch(activityListProvider(groupId)).value;
  final members = ref.watch(memberListProvider(groupId)).value;
  final group = ref.watch(liveGroupProvider(groupId)).value;
  if (entries == null || members == null) return null;
  return ActivityText(
    entries: entries,
    members: members,
    l10n: AppLocalizations.of(context)!,
    locale: Localizations.localeOf(context).toLanguageTag(),
    currencyCode: group?.currencyCode ?? 'VND',
  );
}

/// Every change made to a group, newest first (R-3 AC25). Entries can only
/// be read: nothing here edits or deletes them (AC28).
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final text = _activityText(context, ref, groupId);
    final entries = ref.watch(activityListProvider(groupId)).value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.activity)),
      body: text == null || entries == null
          ? const AppLoadingWidget()
          : entries.isEmpty
              ? EmptyState(icon: Icons.history, title: l10n.activityEmpty)
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _ActivityTile(
                    entry: entries[i],
                    text: text,
                    onTap: () => context
                        .push('/groups/$groupId/activity/${entries[i].id}'),
                  ),
                ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.entry,
    required this.text,
    required this.onTap,
  });

  final ActivityEntry entry;
  final ActivityText text;
  final VoidCallback onTap;

  IconData get _icon => switch (entry.action) {
        ActivityAction.create => Icons.add_circle_outline,
        ActivityAction.update => Icons.edit_outlined,
        ActivityAction.delete => Icons.delete_outline,
        ActivityAction.join => Icons.person_add_alt_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
      leading: Icon(_icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(text.summary(entry)),
      subtitle: Row(
        children: [
          Text(relativeTime(entry.clientTime, l10n, locale)),
          if (!entry.synced) ...[
            const SizedBox(width: 6),
            const UnsyncedMark(),
          ],
        ],
      ),
      onTap: entry.action == ActivityAction.join ? null : onTap,
    );
  }
}

/// One change: what it was and, field by field, old → new values (AC26),
/// or the whole record when it was deleted (AC27).
class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({
    super.key,
    required this.groupId,
    required this.activityId,
  });

  final String groupId;
  final String activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = _activityText(context, ref, groupId);
    final entry = ref
        .watch(activityListProvider(groupId))
        .value
        ?.where((e) => e.id == activityId)
        .firstOrNull;

    if (text == null) return const Scaffold(body: AppLoadingWidget());
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.errorNotFound)),
      );
    }

    final locale = Localizations.localeOf(context).toLanguageTag();
    final time = DateFormat.yMMMd(locale).add_Hm().format(entry.clientTime);
    final fields = text.fields(entry);
    final heading = switch (entry.action) {
      ActivityAction.update => l10n.activityChanges,
      ActivityAction.delete => l10n.activityDetailsWhenDeleted,
      _ => l10n.activityDetails,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.activity)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text.summary(entry), style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(time,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    if (!entry.synced) ...[
                      const SizedBox(width: 6),
                      const UnsyncedMark(),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (fields.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionLabel(heading),
            for (final field in fields) _FieldRow(field: field),
          ],
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});

  final ActivityField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final before = field.before;
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppTheme.gutter, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(field.label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text.rich(
              TextSpan(children: [
                if (before != null) ...[
                  TextSpan(
                    text: before,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const TextSpan(text: '  →  '),
                ],
                TextSpan(text: field.after ?? '—'),
              ]),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
