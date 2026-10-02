import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/expense_failure.dart';
import 'package:simsplit/domain/repositories/member_repository.dart';
import 'package:simsplit/domain/use_cases/expenses/calculate_splits.dart';

/// Ensures the payer and every split participant belong to [groupId].
///
/// Returns [ExpenseFailure.memberNotInGroup] when any id is not a member of
/// the group, or propagates the repository failure.
Future<Either<Failure, Unit>> validateExpenseMembers({
  required MemberRepository memberRepository,
  required String groupId,
  required String paidByMemberId,
  required List<RawSplitInput> splitInputs,
}) async {
  final membersResult =
      await memberRepository.watchMembersByGroup(groupId).first;
  return membersResult.flatMap((members) {
    final memberIds = {for (final m in members) m.id};
    final referenced = [paidByMemberId, ...splitInputs.map((i) => i.memberId)];
    if (referenced.every(memberIds.contains)) return right(unit);
    return left(const ExpenseFailure.memberNotInGroup());
  });
}
