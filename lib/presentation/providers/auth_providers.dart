import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';

part 'auth_providers.g.dart';

/// The signed-in user, or `null` when signed out. Only watch it when
/// [authAvailableProvider] is true.
@Riverpod(keepAlive: true)
Stream<AuthUser?> currentUser(Ref ref) {
  final useCase = ref.watch(watchCurrentUserProvider);
  return useCase(const NoParams()).map(
    (either) => either.fold(
      (failure) => throw FailureException(failure),
      (user) => user,
    ),
  );
}
