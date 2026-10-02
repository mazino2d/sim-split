import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/debt.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/settlement_failure.dart';
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

/// Computes who owes whom in a group and suggests settlement transactions
/// using a greedy heuristic (repeatedly match the largest debtor with the
/// largest creditor). The heuristic yields at most N−1 transactions for N
/// members but is not guaranteed to be the global minimum.
/// Pure business logic — result is NOT stored in DB.
///
/// Returns [SettlementFailure.memberNotInGroup] if an expense, split or
/// settlement references a member that is not part of the group.
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
          (expenses) => settlementsResult.flatMap<DebtSummary>((settlements) {
            // 1. Build net balance map: memberId → net cents
            final balanceMap = <String, int>{
              for (final m in members) m.id: 0,
            };

            // Returns false if [memberId] is unknown so the caller can fail
            // instead of crashing on a missing map entry.
            bool add(String memberId, int delta) {
              final current = balanceMap[memberId];
              if (current == null) return false;
              balanceMap[memberId] = current + delta;
              return true;
            }

            for (final expense in expenses) {
              if (expense.isDeleted) continue;

              // Payer gets credit
              if (!add(expense.paidByMemberId, expense.amountCents)) {
                return left(const SettlementFailure.memberNotInGroup());
              }

              // Each participant owes their share
              for (final split in expense.splits) {
                if (!add(split.memberId, -split.amountCents)) {
                  return left(const SettlementFailure.memberNotInGroup());
                }
              }
            }

            // Apply settled payments
            for (final settlement in settlements) {
              // From pays To → From gets credit, To is debited
              if (!add(settlement.fromMemberId, settlement.amountCents) ||
                  !add(settlement.toMemberId, -settlement.amountCents)) {
                return left(const SettlementFailure.memberNotInGroup());
              }
            }

            // 2. Build member balance list (preserves member order)
            final balances = [
              for (final m in members)
                MemberBalance(
                  member: m,
                  netAmountCents: balanceMap[m.id] ?? 0,
                ),
            ];

            // 3. Greedy debt simplification
            final suggestions = _simplifyDebts(
              balances: balances,
              currencyCode: params.currencyCode,
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

  /// Greedy heuristic: always settle the largest debtor with the largest
  /// creditor. Produces at most N−1 transactions for N members; ties are
  /// broken by member order so the output is deterministic.
  List<Debt> _simplifyDebts({
    required List<MemberBalance> balances,
    required String currencyCode,
  }) {
    // Mutable working copies (positive = owed to, negative = owes)
    final members = [for (final b in balances) b.member];
    final amounts = [for (final b in balances) b.netAmountCents];

    final debts = <Debt>[];

    while (true) {
      // Find max creditor (most positive) and max debtor (most negative)
      var creditorIndex = -1;
      var debtorIndex = -1;
      var maxCredit = 0;
      var maxDebt = 0;

      for (var i = 0; i < amounts.length; i++) {
        if (amounts[i] > maxCredit) {
          maxCredit = amounts[i];
          creditorIndex = i;
        }
        if (amounts[i] < maxDebt) {
          maxDebt = amounts[i];
          debtorIndex = i;
        }
      }

      if (creditorIndex < 0 || debtorIndex < 0) break;

      // Settle the minimum of the two
      final settleAmount = maxCredit < (-maxDebt) ? maxCredit : (-maxDebt);

      debts.add(Debt(
        from: members[debtorIndex],
        to: members[creditorIndex],
        amountCents: settleAmount,
        currencyCode: currencyCode,
      ));

      amounts[debtorIndex] += settleAmount;
      amounts[creditorIndex] -= settleAmount;
    }

    return debts;
  }
}
