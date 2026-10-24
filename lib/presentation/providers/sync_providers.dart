import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';
import 'package:simsplit/domain/entities/telemetry/telemetry_event.dart';
import 'package:simsplit/presentation/utils/tracking.dart';

part 'sync_providers.g.dart';

/// IDs of [groupId]'s records whose latest change has not reached the cloud
/// yet, for the "not synced yet" mark (AC16). Empty without accounts.
@riverpod
Stream<Set<String>> unsyncedRecordIds(Ref ref, String groupId) {
  if (!ref.watch(authAvailableProvider)) return Stream.value(const {});
  return ref.watch(watchUnsyncedRecordIdsProvider)(groupId).map(
        (either) => either.getOrElse((_) => const {}),
      );
}

/// Keeps sync running while an account is signed in: uploads local data on
/// first sign-in, then pushes every change and pulls the account's groups in
/// real time (R-3). Watch it once from the app root.
@Riverpod(keepAlive: true)
Future<void> syncRunner(Ref ref) async {
  if (!ref.watch(authAvailableProvider)) return;
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return;

  final stopSync = ref.read(stopSyncProvider);
  final track = ref.read(trackEventProvider);
  ref.onDispose(() => trackOp(
      track, TelemetryEvent.opStopSync, () => stopSync(const NoParams())));
  final result = await trackOp(track, TelemetryEvent.opStartSync,
      () => ref.read(startSyncProvider)(user));
  result.fold((failure) => debugPrint('[sync] start failed: $failure'), (_) {});
}
