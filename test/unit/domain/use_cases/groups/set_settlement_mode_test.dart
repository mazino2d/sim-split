import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide Group;
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/group_failure.dart';
import 'package:simsplit/domain/use_cases/groups/set_settlement_mode.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockGroupRepository groups;
  late MockMemberRepository members;
  late SetSettlementMode useCase;

  setUpAll(registerEntityFallbacks);

  setUp(() {
    groups = MockGroupRepository();
    members = MockMemberRepository();
    useCase =
        SetSettlementMode(groupRepository: groups, memberRepository: members);
    when(() => groups.getGroup('g1')).thenAnswer((_) async => right(testGroup()
        .copyWith(
            settlementMode: SettlementMode.hub, settlementHubMemberId: 'm1')));
    when(() => groups.updateGroup(any())).thenAnswer((inv) async =>
        right<Failure, Group>(inv.positionalArguments.first as Group));
    when(() => members.watchMembersByGroup('g1')).thenAnswer((_) =>
        Stream.value(right<Failure, List<Member>>(
            [testMember('m1'), testMember('m2')])));
  });

  Group saved() =>
      verify(() => groups.updateGroup(captureAny())).captured.single as Group;

  test('picks a collector in hub mode', () async {
    await useCase(const SetSettlementModeParams(
        groupId: 'g1', mode: SettlementMode.hub, hubMemberId: 'm2'));
    final group = saved();
    expect(group.settlementMode, SettlementMode.hub);
    expect(group.settlementHubMemberId, 'm2');
  });

  test('fewest transfers clears the collector', () async {
    await useCase(const SetSettlementModeParams(
        groupId: 'g1', mode: SettlementMode.simplified, hubMemberId: 'm2'));
    final group = saved();
    expect(group.settlementMode, SettlementMode.simplified);
    expect(group.settlementHubMemberId, isNull);
  });

  test('refuses a collector who is not in the group', () async {
    final result = await useCase(const SetSettlementModeParams(
        groupId: 'g1', mode: SettlementMode.hub, hubMemberId: 'm9'));
    expect(leftOf(result), isA<GroupCollectorNotInGroup>());
    verifyNever(() => groups.updateGroup(any()));
  });
}
