import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/use_cases/profile/my_name.dart';
import 'package:simsplit/presentation/providers/auth_providers.dart';

/// The name last typed for "me" on this device.
const lastMyNameKey = 'my_member_name';

/// The name to prefill for "me" when creating or joining a group (#112): the
/// account's "My name", then the name last used on this device, then the
/// Google name. Null when there is none.
Future<String?> prefilledMyName(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  String? accountName;
  String? displayName;
  if (ref.read(authAvailableProvider)) {
    try {
      // Bounded: a prefill must never hold the form up.
      const wait = Duration(seconds: 3);
      displayName =
          await ref.read(accountDisplayNameProvider.future).timeout(wait);
      accountName =
          await ref.read(accountMemberNameProvider.future).timeout(wait);
    } on Object {
      // A convenience: fall back to what this device knows.
    }
  }
  return prefillMyName(
    accountName: accountName,
    lastUsedOnDevice: prefs.getString(lastMyNameKey),
    displayName: displayName,
  );
}
