import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/repositories/settlement_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class CalculateDebtsParams {
  const CalculateDebtsParams({
    required this.groupId,
    required this.currencyCode,
  });

  final String groupId;
  final String currencyCode;
}

/// Computes who owes whom in a group using the greedy min-transactions algorithm.
/// Pure business logic — result is NOT stored in DB.
class CalculateDebts
    implements AsyncUseCase<DebtSummary, CalculateDebtsParams> {
  const CalculateDebts({
    required MemberRepository memberRepository,
    required ExpenseRepository expenseRepository,
    required SettlementRepository settlementRepository,
  })  : _memberRepository = memberRepository,
        _expenseRepository = expenseRepository,
        _settlementRepository = settlementRepository;

  final MemberRepository _memberRepository;
  final ExpenseRepository _expenseRepository;
  final SettlementRepository _settlementRepository;

  @override
  Future<Either<Failure, DebtSummary>> call(CalculateDebtsParams params) async {
    final membersResult =
        await _memberRepository.watchMembersByGroup(params.groupId).first;
    final expensesResult =
        await _expenseRepository.watchExpensesByGroup(params.groupId).first;
    final settlementsResult = await _settlementRepository
        .watchSettlementsByGroup(params.groupId)
        .first;

    return membersResult.flatMap((members) => expensesResult.flatMap(
          (expenses) => settlementsResult.flatMap((settlements) {
            // 1. Build net balance map: memberId → net cents
            final balanceMap = <String, int>{
              for (final m in members) m.id: 0,
            };

            for (final expense in expenses) {
              if (expense.isDeleted) continue;

              // Payer gets credit
              balanceMap[expense.paidByMemberId] =
                  (balanceMap[expense.paidByMemberId] ?? 0) +
                      expense.amountCents;

              // Each participant owes their share
              for (final split in expense.splits) {
                balanceMap[split.memberId] =
                    (balanceMap[split.memberId] ?? 0) - split.amountCents;
              }
            }

            // Apply settled payments
            for (final settlement in settlements) {
              // From pays To → From gets credit, To is debited
              balanceMap[settlement.fromMemberId] =
                  (balanceMap[settlement.fromMemberId] ?? 0) +
                      settlement.amountCents;
              balanceMap[settlement.toMemberId] =
                  (balanceMap[settlement.toMemberId] ?? 0) -
                      settlement.amountCents;
            }

            // 2. Build member balance list
            final memberMap = {for (final m in members) m.id: m};
            final balances = balanceMap.entries
                .map((e) => MemberBalance(
                      member: memberMap[e.key]!,
                      netAmountCents: e.value,
                    ))
                .toList();

            // 3. Greedy min-transactions debt simplification
            final suggestions = _simplifyDebts(
              balances: balances,
              currencyCode: params.currencyCode,
              memberMap: memberMap,
            );

            return right(DebtSummary(
              groupId: params.groupId,
              currencyCode: params.currencyCode,
              balances: balances,
              suggestions: suggestions,
            ));
          }),
        ));
  }

  /// Greedy algorithm: always settle the largest debtor with the largest creditor.
  /// Produces at most N−1 transactions for N members.
  List<Debt> _simplifyDebts({
    required List<MemberBalance> balances,
    required String currencyCode,
    required Map<String, Member> memberMap,
  }) {
    // Mutable working copies (positive = owed to, negative = owes)
    final amounts = {
      for (final b in balances) b.member.id: b.netAmountCents,
    };

    final debts = <Debt>[];

    while (true) {
      // Find max creditor (most positive) and max debtor (most negative)
      String? maxCreditorId;
      String? maxDebtorId;
      var maxCredit = 0;
      var maxDebt = 0;

      for (final entry in amounts.entries) {
        if (entry.value > maxCredit) {
          maxCredit = entry.value;
          maxCreditorId = entry.key;
        }
        if (entry.value < maxDebt) {
          maxDebt = entry.value;
          maxDebtorId = entry.key;
        }
      }

      if (maxCreditorId == null || maxDebtorId == null) break;

      // Settle the minimum of the two
      final settleAmount = maxCredit < (-maxDebt) ? maxCredit : (-maxDebt);

      debts.add(Debt(
        from: memberMap[maxDebtorId]!,
        to: memberMap[maxCreditorId]!,
        amountCents: settleAmount,
        currencyCode: currencyCode,
      ));

      amounts[maxDebtorId] = amounts[maxDebtorId]! + settleAmount;
      amounts[maxCreditorId] = amounts[maxCreditorId]! - settleAmount;
    }

    return debts;
  }
}
