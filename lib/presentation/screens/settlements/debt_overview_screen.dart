import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/group_providers.dart';
import '../../providers/settlement_providers.dart';
import '../../widgets/common/error_widget.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/settlements/debt_card.dart';

class DebtOverviewScreen extends ConsumerWidget {
  const DebtOverviewScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupDetailProvider(groupId));

    return groupAsync.when(
      data: (group) {
        final debtAsync = ref.watch(
          debtSummaryProvider(groupId, group.currencyCode),
        );
        return Scaffold(
          appBar: AppBar(title: const Text('Số dư nhóm')),
          body: debtAsync.when(
            data: (summary) {
              if (summary.suggestions.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 80, color: Colors.green),
                      SizedBox(height: 16),
                      Text('Đã thanh toán xong!',
                          style: TextStyle(fontSize: 20)),
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
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text('Số dư từng người',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ),
                          for (final balance in summary.balances)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    Color(balance.member.avatarColorValue),
                                child: Text(
                                  balance.member.name
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(balance.member.name),
                              trailing: Text(
                                '${balance.netAmountCents >= 0 ? '+' : ''}'
                                '${(balance.netAmountCents / 100).toStringAsFixed(0)} '
                                '${group.currencyCode}',
                                style: TextStyle(
                                  color: balance.netAmountCents >= 0
                                      ? Colors.green
                                      : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Settlement suggestions
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Gợi ý thanh toán',
                          style: TextStyle(
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
              message: e.toString(),
              onRetry: () => ref.invalidate(
                  debtSummaryProvider(groupId, group.currencyCode)),
            ),
          ),
        );
      },
      loading: () => const Scaffold(body: AppLoadingWidget()),
      error: (e, _) => Scaffold(body: AppErrorWidget(message: e.toString())),
    );
  }
}
