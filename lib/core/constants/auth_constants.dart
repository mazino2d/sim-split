import 'package:simsplit/core/constants/app_env.dart';

/// OAuth client that Firebase Auth trusts for Google sign-in: the Web client
/// "SimSplit Firebase Auth" in the environment's Firebase project. Android
/// sends it as `serverClientId` so the ID token is issued for Firebase. Not a
/// secret.
final googleServerClientId = googleServerClientIdFor(appEnv);

String googleServerClientIdFor(AppEnv env) => switch (env) {
      // TODO(dev-env): placeholder until everything-as-code applies the
      // simsplit-as-se1-dev stack. Replace with the client ID of the Web OAuth
      // client "SimSplit Firebase Auth" in simsplit-as-se1-dev (Terraform
      // output of the dev stack's Identity Platform Google IdP client).
      AppEnv.dev => 'TODO-dev-google-server-client-id',
      AppEnv.prd =>
        '113980760756-039hkt3nurf48vkckkkpfvd4vffm5p3b.apps.googleusercontent.com',
    };
