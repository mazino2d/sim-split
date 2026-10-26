# SimSplit

A group expense tracking and splitting app — friends share a group, log expenses together
and see the same balances, and every change is on record.

Use it on the web at **[simsplit.web.app](https://simsplit.web.app)** or on Android from
[Google Play](https://play.google.com/store/apps/details?id=com.mazino2d.simsplit); iOS
follows once the Apple Developer account is active.

---

## Features

- **Groups** — Create groups for trips, shared housing, or any shared expense
- **4 split types** — Equal / Percentage / Exact amount / Shares ratio
- **Automatic debt simplification** — Minimizes the number of transactions needed to settle
- **Settlement recording** — Track payment history
- **Shared groups** — Sign in with Google, invite friends with a link, see changes live
- **Activity history** — Who added, edited or deleted what, with old → new values
- **Offline after sign-in** — Changes apply at once and sync when the connection is back
- **Multilingual** — English and Vietnamese

---

## Tech Stack

| Concern | Choice |
| --- | --- |
| Framework | Flutter 3.47.x (Android, iOS, web) |
| State management | Riverpod |
| Local database | Drift / SQLite (WASM on web) |
| Backend | Firebase Auth + Cloud Firestore (`simsplit-as-se1-prd`, and `simsplit-as-se1-dev` for dev builds; asia-southeast1); Hosting serves the web app |
| Architecture | Clean Architecture |
| CI/CD | GitHub Actions + Fastlane |

---

## Getting Started

### Requirements

- Flutter SDK 3.47.x (stable) — [install guide](https://docs.flutter.dev/get-started/install)
- Android Studio / Android SDK (for Android)
- Xcode (for iOS)
- `curl` (used by `scripts/setup.sh` to fetch the web database assets)

For web and tests only, GitHub Codespaces needs no local install — see
[CONTRIBUTING.md](CONTRIBUTING.md#codespaces).

### First run

```bash
# Clone the repo
git clone https://github.com/mazino2d/sim-split.git
cd sim-split

# Bootstrap: generates platform code, installs dependencies, runs code generation,
# and downloads the web database assets matching pubspec.lock
bash scripts/setup.sh

# Run the app (App Check is enforced: debug builds need the token in .env.local).
# Android needs a flavor that matches APP_ENV in .env.local (see Environments).
cp .env.example .env.local
flutter run --flavor prd --dart-define-from-file=.env.local
```

### Environments

| | dev | prd |
| --- | --- | --- |
| `--dart-define=APP_ENV=` | `dev` | `prd` (the default) |
| Android `--flavor` | `dev` | `prd` |
| Firebase project | `simsplit-as-se1-dev` | `simsplit-as-se1-prd` |
| Android package (Play app) | `com.mazino2d.simsplit.dev` ("SimSplit Dev") | `com.mazino2d.simsplit` ("SimSplit") |
| Web app | [simsplit-as-se1-dev.web.app](https://simsplit-as-se1-dev.web.app) | [simsplit.web.app](https://simsplit.web.app) |
| Ships on | every push to `main` | tags only: `vYYYY.M.D-rc.N` → Play closed testing, `vYYYY.M.D` → Play production, web, Firestore rules and indexes |

Android builds need `--flavor` (a build without it fails). Web and iOS have no
flavors; iOS always uses `prd`. Telemetry (R-4) is prd only. The Firebase options of
the two projects are in `lib/firebase_options.dart` (prd) and
`lib/firebase_options_dev.dart` (dev).

### Running on the web

The web build stores data in the browser (OPFS, or IndexedDB as a fallback) using
Drift's WASM backend. It needs two files in `web/` whose versions must match
`pubspec.lock`:

- `web/drift_worker.js` — from the [drift release](https://github.com/simolus3/drift/releases) `drift-<version>`
- `web/sqlite3.wasm` — from the [sqlite3.dart release](https://github.com/simolus3/sqlite3.dart/releases) `sqlite3-<version>`

`scripts/setup.sh` downloads both. Re-run it (or just its web section) after
upgrading `drift` or `sqlite3`.

```bash
# Debug run in Chrome
flutter run -d chrome

# Release build (output in build/web)
flutter build web --release
```

### Common commands

```bash
# Run tests
flutter test

# Code generation (run after modifying models, DAOs, or providers)
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n

# Run all generators (icons, splash screen, localizations)
bash scripts/generate.sh

# Debug APK (no keystore needed)
flutter build apk --debug --flavor prd
```

Release builds (`flutter build appbundle --release --flavor prd`, `flutter build apk --release --flavor prd`)
**require** `android/key.properties`; the Gradle build fails with a clear error if
it is missing instead of falling back to the debug key.

---

## Architecture

Strict **Clean Architecture** with three layers:

```text
lib/
├── domain/          # Pure Dart — entities, failures, repository interfaces, use cases
├── data/            # Drift tables, DAOs, mappers, Drift + Firebase repositories, Firestore sync (sync/)
├── presentation/    # Riverpod providers/notifiers, go_router, screens, widgets
└── core/
    └── di/          # Dependency injection (DB → DAO → Repo → UseCase)
```

> See full architecture guidelines: [AGENTS.md](AGENTS.md)

### Key rules

- `lib/domain/` is pure Dart — no Flutter, Drift, Firebase, Riverpod or go_router imports; presentation never imports data
- Money is always **integer cents** (`amountCents: int`) — never `double`
- Error handling uses `Either<Failure, T>` from `fpdart`

---

## CI/CD

| Workflow | Trigger | Result |
| --- | --- | --- |
| `pr_validate` | Every PR → `main` | Parallel format/analyze/test, store-metadata check, Firestore rules tests, telemetry endpoint tests and actionlint, each skipped unless its files change; `PR Validation` is the required check |
| `build_android` | Push to `main` touching app code, manual (`workflow_dispatch`), or called by `release` / `release_candidate` | Signed AAB → Google Play. Push and manual runs build the `dev` flavor for SimSplit Dev (`com.mazino2d.simsplit.dev`): on push straight to internal testers, manual runs pick the track (default `internal`). Tags build the `prd` flavor for `com.mazino2d.simsplit` |
| `build_ios` | Manual (`workflow_dispatch`) | Unsigned iOS build (signing disabled until the Apple account is active) |
| `release_candidate` | Push a `vYYYY.M.D-rc.N` tag | Uploads the AAB as `YYYY.M.D-rc.N` with release notes to the closed testing track (`alpha`), creates a GitHub pre-release |
| `release` | Push a `vYYYY.M.D` tag | Validates the tag, uploads the AAB with release notes to the `production` track as a 20 % staged rollout (sent for review), deploys the web app and Firestore rules and indexes to prd (`firebase_deploy`), creates a GitHub Release |
| `play_rollout` | Manual, from `main` | Widens the production rollout to 50 % or 100 %, or halts / resumes it |
| `play_metadata` | Push to `main` touching `android/fastlane/metadata/**`, or manual (dry run by default) | Syncs the Play store listing, images, contact details and Data safety form to both apps (prd, then SimSplit Dev under its own title) — see [android/fastlane/README.md](android/fastlane/README.md) |
| `firebase_deploy` | Push to `main` touching the app, `web/` or `firebase/**`, manual, or called by `release` | Builds the web app and deploys it with the Firestore rules and indexes: to dev ([simsplit-as-se1-dev.web.app](https://simsplit-as-se1-dev.web.app)) from `main` and manual runs on a branch, to prd ([simsplit.web.app](https://simsplit.web.app)) from a `vYYYY.M.D` tag |
| `telemetry_deploy` | Push to `main` touching `services/telemetry/**`, or manual | Builds the error report and usage endpoint (R-4) and deploys it to Cloud Run |
| `pages` | Push to `main` touching `docs/**`, or manual; PRs build only | Publishes `docs/` (landing page, privacy policy) to [mazino2d.github.io/sim-split](https://mazino2d.github.io/sim-split/) |
| `codeql` | Workflow changes, weekly | CodeQL scan of the workflows |

Shared logic comes from [mazino2d/github-workflows](https://github.com/mazino2d/github-workflows) (`@v1`): `pages`, `codeql` and the actionlint job of `pr_validate` call its reusable workflows, and `.github/actions/flutter-setup` pins the Flutter version for its shared `flutter-setup` action.

### versionCode

Google Play needs a unique, increasing `versionCode` for every upload. CI ignores
the `+N` build number in `pubspec.yaml` and passes
`--build-number=<minutes since 2026-01-01 UTC>` to `flutter build appbundle`, which
is monotonic across manual and tag-triggered runs. The `versionName` comes from the
tag (`YYYY.M.D`, `YYYY.M.D-rc.N`), or is `YYYY.M.D-dev.<sha7>` for untagged builds;
`pubspec.yaml`'s version is only checked against the production tag.

### Required GitHub Secrets

**Android:**

```text
ANDROID_KEYSTORE_BASE64   ANDROID_STORE_PASSWORD
ANDROID_KEY_PASSWORD      ANDROID_KEY_ALIAS
```

**Google Play upload** needs no secret: `build_android.yml` authenticates with
Workload Identity Federation as
`gha-play-publisher@simsplit-as-se1-prd.iam.gserviceaccount.com`, defined in
[everything-as-code](https://github.com/mazino2d/everything-as-code/blob/main/terraform/gcp/simsplit-as-se1-prd/github_actions.tf).
Only `main` and `vX.Y.Z` tags can use it. It uploads both Play apps (SimSplit and
SimSplit Dev), so it must be invited in Play Console → Users and permissions with the
app permissions listed in
[android/fastlane/README.md](android/fastlane/README.md#play-console-access-for-ci)
(release + Manage store presence).

**iOS (not needed until the Apple account is active):**

```text
IOS_DISTRIBUTION_CERT_BASE64   IOS_CERT_PASSWORD
IOS_PROVISION_PROFILE_BASE64   KEYCHAIN_PASSWORD
ASC_KEY_ID   ASC_ISSUER_ID   ASC_PRIVATE_KEY_BASE64
```

### Generate Android upload keystore (one time only)

```bash
keytool -genkey -v \
  -keystore simsplit.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias simsplit

# Base64-encode and add to GitHub Secrets as ANDROID_KEYSTORE_BASE64
base64 -i simsplit.jks | pbcopy
```

For local release builds, copy `android/key.properties.example` to
`android/key.properties` and place the keystore at `android/app/simsplit.jks`.
Never commit either file.

---

## Releasing

### Internal testing build

Every merge to `main` that changes app code (`lib/`, `android/`, `assets/`,
`pubspec.lock`) uploads a build to the Play **internal** track, released to internal
testers at once. To upload another branch's build or pick another track: GitHub →
Actions → **Build Android** → *Run workflow* (default `internal`, `draft`).

### Closed test (release candidate)

```bash
git tag v2026.10.25-rc.1      # the day it is cut, then rc.2, rc.3 …
git push origin v2026.10.25-rc.1
```

`release_candidate.yml` builds `main` at that tag as `2026.10.25-rc.1` and uploads it
to the closed testing track with the notes in `android/fastlane/whatsnew/`.

### Production release

```bash
# 1. Set the version in pubspec.yaml to today's CalVer date, YYYY.M.D without
#    zero padding (e.g. 2026.10.22+6). The +N part is overridden in CI.
# 2. Write the release notes in android/fastlane/whatsnew/whatsnew-{en-US,vi}
#    (max 500 chars each)
# 3. Commit and merge the change to main
git tag v2026.10.22
git push origin v2026.10.22
```

`release.yml` checks that the tag matches the `pubspec.yaml` version, builds and
uploads the AAB with the release notes to the Play **production** track as a staged
rollout at 20 %, and creates a GitHub Release with the AAB attached. Managed
publishing is off, so the upload goes to review at once and reaches 20 % of users when
approved. After checking Android vitals, widen it with GitHub → Actions → **Play
Rollout** (`50%`, `100%`, or `halt` / `resume`).

---

## Privacy

SimSplit keeps your Google account's name and email in Firebase Authentication and your
groups in Cloud Firestore; a group is visible only to its members. Signing in agrees to usage tracking
(linked to the account) and anonymous error reports (can be turned off in Settings → Diagnostics),
sent only to the app's own endpoint and analysed in the maintainer's BigQuery warehouse. No ads and
no third-party analytics. See
[docs/privacy-policy.html](docs/privacy-policy.html).

---

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). Report security issues privately as described in
[SECURITY.md](SECURITY.md).

---

## License

[MIT](LICENSE)
