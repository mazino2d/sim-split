# Contributing to SimSplit

Thanks for helping out. SimSplit is a small project with one maintainer, so a
little coordination up front saves everyone time.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- **Bugs:** open a [bug report](https://github.com/mazino2d/sim-split/issues/new?template=bug_report.yml).
  A small, obvious fix (a typo, a crash with a clear cause) can go straight to a
  pull request.
- **Features and larger changes:** open a
  [feature request](https://github.com/mazino2d/sim-split/issues/new?template=feature_request.yml)
  first and wait for a go-ahead before writing code. Ideas are weighed against the
  [product strategy](docs/product/strategy.md) and [roadmap](docs/product/roadmap.md),
  and some things are deliberate non-goals.
- **Security issues:** do not open a public issue. Follow [SECURITY.md](SECURITY.md).

## Set up

You need Flutter 3.47.x (stable), plus the Android SDK or Xcode for mobile builds.

```bash
git clone https://github.com/mazino2d/sim-split.git
cd sim-split
bash scripts/setup.sh                                      # bootstrap once
cp .env.example .env.local                                 # local build settings (gitignored)
flutter run -d chrome --dart-define-from-file=.env.local   # drop -d chrome for a device
```

See the [README](README.md) for web, release and CI details.

### Codespaces

Open the repo in [GitHub Codespaces](https://github.com/codespaces/new?repo=mazino2d/sim-split)
(or "Reopen in Container" in VS Code) to skip the local install. The container in
`.devcontainer/` has Flutter, Java and Node, and runs code generation on creation, so
the CI checks and the rules tests work straight away. It has no Android SDK or Xcode.
Run the web app on the forwarded port 3000:

```bash
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 3000 --dart-define-from-file=.env.local
```

Google sign-in only works on domains authorized in Firebase Auth, which the
`*.app.github.dev` preview URL is not.

The container also has Claude Code. Sign in once with `claude` (`/login`); the login
survives rebuilds. To drive it from claude.ai or the Claude app, start
`claude remote-control` in a terminal and keep the codespace running — it stops after
its idle timeout (Settings → Codespaces → Default idle timeout). `gh` is already
signed in with the codespace's token, which can push branches and open pull requests
on this repo.

## Rules of the codebase

[AGENTS.md](AGENTS.md) is the full guide; the short version:

1. **Clean Architecture is strict.** `lib/domain/` is pure Dart — no Flutter,
   Drift, Firebase, Riverpod or go_router imports. Presentation never imports data.
2. **Money is `int` cents, never `double`.** Splits always sum exactly to the total.
3. **Errors are `Either<Failure, T>`** (fpdart) in domain and data, not exceptions.
4. **Never hand-edit generated files** (`*.g.dart`, `*.freezed.dart`) — rerun codegen.
5. **Every user-facing string** goes in both `lib/core/l10n/app_en.arb` and
   `app_vi.arb`, then run `flutter gen-l10n`.
6. **Every Firestore rules change needs a test** in `firebase/test/`.
7. **Never commit secrets** such as `android/key.properties`, `*.jks` or `AuthKey_*.p8`.

Code, comments, docs and commit messages are written in English.

## Before you open a pull request

Run what CI runs:

```bash
dart run build_runner build --delete-conflicting-outputs   # if models / DAOs / providers changed
flutter analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
flutter test
```

If you changed `firebase/firestore.rules`, also run the rules tests on the emulator:

```bash
npm ci --prefix firebase/test
npx firebase-tools emulators:exec --only firestore --project demo-simsplit \
  "npm --prefix firebase/test test"
```

## Pull requests

- Branch from `main` and keep one change per pull request.
- Title in [Conventional Commits](https://www.conventionalcommits.org/) form,
  e.g. `feat(expenses): add receipt photos` or `fix(sync): retry on timeout`.
- Fill in the pull request template; add before/after screenshots for UI changes.
- Add or update tests for changed use cases, repositories and rules.
- `PR Validation` must pass. Pull requests are squash-merged, so the title becomes
  the commit message on `main`.

## License

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE).
