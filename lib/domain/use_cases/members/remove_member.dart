import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/settlement_failure.dart';
import 'package:simsplit/domain/repositories/expense_repository.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

class RemoveMemberParams {
  const RemoveMemberParams({required this.memberId, required this.groupId});
  final String memberId;
  final String groupId;
}

class RemoveMember implements AsyncUseCase<Unit, RemoveMemberParams> {
  const RemoveMember({
    required MemberRepository memberRepository,
    required ExpenseRepository expenseRepository,
  })  : _memberRepository = memberRepository,
        _expenseRepository = expenseRepository;

  final MemberRepository _memberRepository;
  final ExpenseRepository _expenseRepository;

  @override
  Future<Either<Failure, Unit>> call(RemoveMemberParams params) async {
    // Check if member has any active (non-deleted) expenses as payer or participant
    final expensesResult =
        await _expenseRepository.watchExpensesByGroup(params.groupId).first;

    return expensesResult.fold<Future<Either<Failure, Unit>>>(
      (failure) async => left(failure),
      (expenses) {
        final hasExpenses = expenses.any(
          (e) =>
              !e.isDeleted &&
              (e.paidByMemberId == params.memberId ||
                  e.splits.any((s) => s.memberId == params.memberId)),
        );

        if (hasExpenses) {
          return Future.value(
              left(const SettlementFailure.memberHasUnsettledDebts()));
        }

        return _memberRepository.removeMember(params.memberId);
      },
    );
  }
}
