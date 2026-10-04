import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';

part 'sync_providers.g.dart';

/// Keeps sync running while an account is signed in: uploads local data on
/// first sign-in, then pushes every change (R-3). Watch it once from the app
/// root.
@Riverpod(keepAlive: true)
Future<void> syncRunner(Ref ref) async {
  if (!ref.watch(authAvailableProvider)) return;
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return;

  final stopSync = ref.read(stopSyncProvider);
  ref.onDispose(() => stopSync(const NoParams()));
  await ref.read(startSyncProvider)(user);
}
