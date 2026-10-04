import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/members/update_member.dart';
import 'package:simsplit/presentation/providers/group_providers.dart';
import 'package:simsplit/presentation/widgets/members/who_is_me_card.dart';

import '../helpers/mocks.dart';

class _MockUpdateMember extends Mock implements UpdateMember {}

void main() {
  late _MockUpdateMember updateMember;

  setUpAll(() => registerFallbackValue(UpdateMemberParams(
        id: '',
        groupId: '',
        name: '',
        avatarColorValue: 0,
        isMe: false,
        createdAt: testDate,
      )));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    updateMember = _MockUpdateMember();
    when(() => updateMember(any()))
        .thenAnswer((_) async => right<Failure, Member>(testMember('m2')));
  });

  Future<void> pump(
    WidgetTester tester, {
    required List<Member> members,
    bool authAvailable = true,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authAvailableProvider.overrideWithValue(authAvailable),
        memberListProvider('g1').overrideWith((ref) => Stream.value(members)),
        updateMemberProvider.overrideWithValue(updateMember),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: WhoIsMeCard(groupId: 'g1')),
      ),
    ));
    await tester.pumpAndSettle();
  }

  final friends = [
    testMember('m1', name: 'An'),
    testMember('m2', name: 'Binh')
  ];

  testWidgets('asks which member you are and links the one you pick (AC7)',
      (tester) async {
    await pump(tester, members: friends);

    expect(find.text('Which one is you?'), findsOneWidget);
    await tester.tap(find.text('Binh'));
    await tester.pumpAndSettle();

    final params = verify(() => updateMember(captureAny())).captured.single
        as UpdateMemberParams;
    expect((params.id, params.isMe), ('m2', true));
    expect(find.text('Which one is you?'), findsNothing);
  });

  testWidgets('asks only once', (tester) async {
    await pump(tester, members: friends);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Which one is you?'), findsNothing);

    await pump(tester, members: friends);

    expect(find.text('Which one is you?'), findsNothing);
  });

  testWidgets('stays hidden when there is nothing to ask', (tester) async {
    await pump(tester, members: [friends.first]);
    expect(find.text('Which one is you?'), findsNothing);

    await pump(tester,
        members: [friends.first.copyWith(isMe: true), friends.last]);
    expect(find.text('Which one is you?'), findsNothing);

    await pump(tester, members: friends, authAvailable: false);
    expect(find.text('Which one is you?'), findsNothing);
  });
}
