import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/theme/app_theme.dart';
import 'package:simsplit/presentation/widgets/common/empty_state.dart';
import 'package:simsplit/presentation/widgets/common/error_widget.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';
import 'package:simsplit/presentation/widgets/common/money_text.dart';
import 'package:simsplit/presentation/widgets/common/section_label.dart';
import 'package:simsplit/presentation/widgets/groups/group_card.dart';

class GroupListScreen extends ConsumerStatefulWidget {
  const GroupListScreen({super.key});

  @override
  ConsumerState<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends ConsumerState<GroupListScreen> {
  @override
  void initState() {
    super.initState();
    // Remove splash after the first frame is fully rasterized,
    // ensuring icon fonts are already loaded before user sees the UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final groupsAsync = ref.watch(groupListProvider);
    final activeGroups =
        groupsAsync.value?.where((g) => !g.isArchived).toList() ?? const [];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            toolbarHeight: 72,
            titleSpacing: AppTheme.gutter,
            title: Text(
              l10n.appTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: l10n.settings,
                onPressed: () => context.push('/settings'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          ...groupsAsync.when(
            data: (_) => activeGroups.isEmpty
                ? [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.luggage_outlined,
                        title: l10n.noGroups,
                        message: l10n.noGroupsHint,
                        actionLabel: l10n.createGroup,
                        onAction: () => context.push('/groups/form'),
                      ),
                    ),
                  ]
                : [
                    SliverToBoxAdapter(
                      child: _BalanceSummary(groups: activeGroups),
                    ),
                    SliverToBoxAdapter(child: SectionLabel(l10n.groupsTitle)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          AppTheme.gutter, 0, AppTheme.gutter, 120),
                      sliver: SliverList.separated(
                        itemCount: activeGroups.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            GroupCard(group: activeGroups[index]),
                      ),
                    ),
                  ],
            loading: () => const [
              SliverFillRemaining(child: AppLoadingWidget()),
            ],
            error: (e, _) => [
              SliverFillRemaining(
                child: AppErrorWidget(
                  error: e,
                  onRetry: () => ref.invalidate(groupListProvider),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: activeGroups.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/groups/form'),
              icon: const Icon(Icons.add),
              label: Text(l10n.newGroup),
            ),
    );
  }
}

/// What "me" is owed and owes across all groups, per currency. Owed and owing
/// amounts are shown separately rather than netted: they involve different
/// people, so netting them would hide who needs to pay.
class _BalanceSummary extends ConsumerWidget {
  const _BalanceSummary({required this.groups});

  final List<Group> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final owed = <String, int>{};
    final owe = <String, int>{};
    var hasMe = false;
    for (final g in groups) {
      final me = ref
          .watch(memberListProvider(g.id))
          .value
          ?.where((m) => m.isMe)
          .firstOrNull;
      if (me == null) continue;
      hasMe = true;
      final net = ref
              .watch(debtSummaryProvider(g.id, g.currencyCode))
              .value
              ?.balances
              .where((b) => b.member.id == me.id)
              .firstOrNull
              ?.netAmountCents ??
          0;
      owed.update(g.currencyCode, (v) => v + (net > 0 ? net : 0),
          ifAbsent: () => net > 0 ? net : 0);
      owe.update(g.currencyCode, (v) => v + (net < 0 ? -net : 0),
          ifAbsent: () => net < 0 ? -net : 0);
    }
    if (!hasMe) return const SizedBox.shrink();

    final currencies =
        owed.keys.where((c) => owed[c]! != 0 || owe[c]! != 0).toList()..sort();

    final labelStyle =
        theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final amountStyle = theme.textTheme.headlineSmall;

    Widget column(String label, int cents, String currency, Color? color) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: labelStyle),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(cents, currency,
                    style: amountStyle,
                    color: cents == 0 ? cs.onSurfaceVariant : color),
              ),
            ],
          ),
        );

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppTheme.gutter, 8, AppTheme.gutter, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        child: currencies.isEmpty
            ? Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: context.money.positive),
                  const SizedBox(width: 12),
                  Text(l10n.allSettledHome, style: theme.textTheme.titleMedium),
                ],
              )
            : Column(
                children: [
                  for (final (i, c) in currencies.indexed) ...[
                    if (i > 0) const Divider(height: 32),
                    Row(
                      children: [
                        column(l10n.totalOwedToYou, owed[c]!, c,
                            context.money.positive),
                        const SizedBox(width: 16),
                        column(l10n.totalYouOwe, owe[c]!, c,
                            context.money.negative),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
