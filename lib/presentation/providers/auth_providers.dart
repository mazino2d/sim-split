import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/core/platform/user_agent.dart';
import 'package:simsplit/core/utils/in_app_browser.dart';
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

/// The name this account goes by in groups (#112): set in Settings, kept
/// with the account. Null when signed out or not set. Kept alive so forms
/// can read it once without watching; recomputed when the account changes.
@Riverpod(keepAlive: true)
Future<String?> accountMemberName(Ref ref) async {
  if (!ref.watch(authAvailableProvider)) return null;
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return null;
  final result = await ref.watch(getMyNameProvider)(const NoParams());
  return result.getOrElse((_) => null);
}

/// The Google account name, the last fallback for "me" (#112). A future,
/// so a form can await it once even before the account stream is watched.
@Riverpod(keepAlive: true)
Future<String?> accountDisplayName(Ref ref) async {
  if (!ref.watch(authAvailableProvider)) return null;
  return (await ref.watch(currentUserProvider.future))?.displayName;
}

/// The chat or social app whose built-in browser shows the web app, where
/// Google sign-in doesn't work (#109); `null` in a regular browser and in
/// the native apps.
@riverpod
String? inAppBrowser(Ref ref) => kIsWeb ? inAppBrowserName(userAgent()) : null;

/// The link to open in a regular browser from the sign-in gate: the invite
/// link kept as `from` when there is one, otherwise the app's start page.
@riverpod
Uri signInPageLink(Ref ref) => signInLinkFor(Uri.base);

/// [signInPageLinkProvider] for the page at [page].
Uri signInLinkFor(Uri page) {
  final from = page.queryParameters['from'];
  // Only a path on this site: `//host` would point elsewhere.
  final path = from != null && from.startsWith('/') && !from.startsWith('//')
      ? from
      : '/';
  return Uri.parse(page.origin).resolve(path);
}
