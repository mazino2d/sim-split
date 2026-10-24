/// The backend a build talks to, set with `--dart-define=APP_ENV=dev|prd`.
///
/// - `dev`: Firebase project `simsplit-as-se1-dev`, web app at
///   `simsplit-dev.web.app`, Android package `com.mazino2d.simsplit.dev`
///   (build with `--flavor dev`). Pushes to `main` ship here.
/// - `prd` (default): Firebase project `simsplit-as-se1-prd`, web app at
///   `simsplit.web.app`, Android package `com.mazino2d.simsplit`
///   (`--flavor prd`). Only release tags ship here.
enum AppEnv {
  dev,
  prd;

  /// Parses an `APP_ENV` value. Empty means [prd]; anything else that is not
  /// `dev` or `prd` is a build mistake and throws, so a typo never ships a
  /// build that silently talks to the wrong backend.
  static AppEnv parse(String value) => switch (value) {
        '' || 'prd' => AppEnv.prd,
        'dev' => AppEnv.dev,
        _ =>
          throw ArgumentError.value(value, 'APP_ENV', 'must be "dev" or "prd"'),
      };

  /// Origin of the web app on Firebase Hosting, where invite links open.
  Uri get webOrigin => switch (this) {
        AppEnv.dev => Uri.parse('https://simsplit-dev.web.app'),
        AppEnv.prd => Uri.parse('https://simsplit.web.app'),
      };
}

/// The environment of this build.
final appEnv =
    AppEnv.parse(const String.fromEnvironment('APP_ENV', defaultValue: 'prd'));
