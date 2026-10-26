import 'package:simsplit/core/constants/app_env.dart';

/// OAuth client that Firebase Auth trusts for Google sign-in: the Web client
/// "SimSplit Firebase Auth" ("SimSplit Dev Firebase Auth" on dev) in the
/// environment's Firebase project. Android sends it as `serverClientId` so the
/// ID token is issued for Firebase. Not a secret.
final googleServerClientId = googleServerClientIdFor(appEnv);

String googleServerClientIdFor(AppEnv env) => switch (env) {
      AppEnv.dev =>
        '158855278019-s9m1cprep0b22t19v527j5icmfej2pug.apps.googleusercontent.com',
      AppEnv.prd =>
        '113980760756-039hkt3nurf48vkckkkpfvd4vffm5p3b.apps.googleusercontent.com',
    };
