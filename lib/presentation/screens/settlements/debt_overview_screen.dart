import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/providers/settlement_providers.dart';
import 'package:simsplit/presentation/widgets/common/error_widget.dart';
import 'package:simsplit/presentation/widgets/common/loading_widget.dart';
import 'package:simsplit/presentation/widgets/settlements/debt_card.dart';
import 'package:simsplit/presentation/widgets/common/member_avatar.dart';
import 'package:simsplit/presentation/widgets/common/money_text.dart';

class DebtOverviewScreen extends ConsumerWidget {
  const DebtOverviewScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final groupAsync = ref.watch(groupDetailProvider(groupId));

    return groupAsync.when(
      data: (group) {
        final debtAsync = ref.watch(
          debtSummaryProvider(groupId, group.currencyCode),
        );
        return Scaffold(
          appBar: AppBar(title: Text(l10n.groupBalancesTitle)),
          body: debtAsync.when(
            data: (summary) {
              if (summary.suggestions.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 80,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(l10n.settledUp,
                          style: const TextStyle(fontSize: 20)),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  // Per-member balances
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(l10n.balances,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          for (final balance in summary.balances)
                            ListTile(
                              leading: MemberAvatar(
                                  member: balance.member, size: 36),
                              title: Text(balance.member.name),
                              trailing: MoneyText(
                                balance.netAmountCents,
                                group.currencyCode,
                                signed: true,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Settlement suggestions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(l10n.suggestedSettlements,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: summary.suggestions.length,
                      itemBuilder: (ctx, i) => DebtCard(
                        debt: summary.suggestions[i],
                        currencyCode: group.currencyCode,
                        onSettle: () => context.push(
                          '/groups/$groupId/settle',
                          extra: {
                            'fromMemberId': summary.suggestions[i].from.id,
                            'toMemberId': summary.suggestions[i].to.id,
                            'amountCents': summary.suggestions[i].amountCents,
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const AppLoadingWidget(),
            error: (e, _) => AppErrorWidget(
              error: e,
              onRetry: () => ref
                  .invalidate(debtSummaryProvider(groupId, group.currencyCode)),
            ),
          ),
        );
      },
      loading: () => const Scaffold(body: AppLoadingWidget()),
      error: (e, _) => Scaffold(body: AppErrorWidget(error: e)),
    );
  }
}
