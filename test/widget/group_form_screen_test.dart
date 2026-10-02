import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide Group;
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/l10n/generated/app_localizations.dart';
import 'package:simsplit/domain/entities/group.dart';
import 'package:simsplit/domain/entities/member.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/use_cases/groups/create_group.dart';
import 'package:simsplit/domain/use_cases/members/add_member.dart';
import 'package:simsplit/presentation/screens/groups/group_form_screen.dart';

import '../helpers/mocks.dart';

class _MockCreateGroup extends Mock implements CreateGroup {}

class _MockAddMember extends Mock implements AddMember {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const CreateGroupParams(name: '', currencyCode: 'VND'),
    );
    registerFallbackValue(const AddMemberParams(groupId: '', name: ''));
  });

  testWidgets(
      'keeps notifiers alive across a slow save and finishes it '
      '(regression: spinner never stopped)', (tester) async {
    final createGroup = _MockCreateGroup();
    final addMember = _MockAddMember();
    // A save slower than one frame is what exposed the bug on web: the build
    // during saving stopped watching the auto-dispose notifiers, so they were
    // disposed before the member step ran.
    when(() => createGroup(any())).thenAnswer(
      (_) => Future.delayed(
        const Duration(seconds: 1),
        () => right<Failure, Group>(testGroup()),
      ),
    );
    when(() => addMember(any())).thenAnswer(
      (_) async => right<Failure, Member>(testMember('me')),
    );

    final router = GoRouter(
      initialLocation: '/form',
      routes: [
        GoRoute(
          path: '/form',
          builder: (_, __) => const GroupFormScreen(),
        ),
        GoRoute(
          path: '/groups/:groupId',
          builder: (_, __) => const Scaffold(body: Text('detail')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          createGroupProvider.overrideWithValue(createGroup),
          addMemberProvider.overrideWithValue(addMember),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Trip');
    await tester.enterText(fields.at(1), 'Me');
    await tester.tap(find.byIcon(Icons.check));

    // Several frames while the save is in flight, then let it complete.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    verify(() => addMember(any())).called(1);
    expect(find.text('detail'), findsOneWidget);
  });
}
