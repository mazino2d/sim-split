# SimSplit

A group expense tracking and splitting app — works fully **offline**, no account required.

Available on Android and iOS.

---

## Features

- **Groups** — Create groups for trips, shared housing, or any shared expense
- **4 split types** — Equal / Percentage / Exact amount / Shares ratio
- **Automatic debt simplification** — Minimizes the number of transactions needed to settle
- **Settlement recording** — Track payment history
- **Offline-first** — No internet required; all data stored on device
- **Multilingual** — English and Vietnamese

---

## Tech Stack

| Concern | Choice |
| --- | --- |
| Framework | Flutter 3.24 (Android + iOS) |
| State management | Riverpod 2.5 |
| Local database | Drift / SQLite |
| Architecture | Clean Architecture |
| CI/CD | GitHub Actions + Fastlane |

---

## Getting Started

### Requirements

- Flutter SDK 3.24+ — [install guide](https://flutter.dev/docs/get-started/install/macos)
- Xcode 15+ (for iOS)
- Android Studio / Android SDK (for Android)

### First run

```bash
# Clone the repo
git clone <repo-url>
cd sim-split

# Bootstrap: generates platform code, installs dependencies, runs code generation
bash scripts/setup.sh

# Run the app
flutter run
```

### Common commands

```bash
# Run tests
flutter test

# Code generation (run after modifying models, DAOs, or providers)
dart run build_runner build --delete-conflicting-outputs

# Run all generators (icons, splash screen, localizations)
bash scripts/generate.sh

# Build Android release AAB
flutter build appbundle --release

# Build iOS release IPA
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

---

## Architecture

Strict **Clean Architecture** with three layers:

```text
lib/
├── domain/          # Pure Dart — entities, failures, repository interfaces, use cases
├── data/            # Drift tables, DAOs, mappers, repository implementations
├── presentation/    # Riverpod providers/notifiers, go_router, screens, widgets
└── core/
    └── di/          # Dependency injection (DB → DAO → Repo → UseCase)
```

> See full architecture guidelines: [.github/copilot-instructions.md](.github/copilot-instructions.md)

### Key rules

- `lib/domain/` must not import Flutter, Drift, or Riverpod
- Money is always **integer cents** (`amountCents: int`) — never `double`
- Error handling uses `Either<Failure, T>` from `fpdart`

---

## CI/CD

| Workflow | Trigger | Result |
| --- | --- | --- |
| `pr_validate` | Every PR → `main` | Lint + format + tests |
| `build_android` | Push → `main` | AAB → Play Store internal track |
| `build_ios` | Push → `main` | IPA → TestFlight |
| `release` | `git tag v1.0.0` | Production release to both stores |

### Required GitHub Secrets

**Android:**

```text
ANDROID_KEYSTORE_BASE64   ANDROID_STORE_PASSWORD
ANDROID_KEY_PASSWORD      ANDROID_KEY_ALIAS
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON
```

**iOS:**

```text
IOS_DISTRIBUTION_CERT_BASE64   IOS_CERT_PASSWORD
IOS_PROVISION_PROFILE_BASE64   KEYCHAIN_PASSWORD
ASC_KEY_ID   ASC_ISSUER_ID   ASC_PRIVATE_KEY_BASE64
```

### Generate Android keystore (one time only)

```bash
keytool -genkey -v \
  -keystore simsplit.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias simsplit

# Base64-encode and add to GitHub Secrets as ANDROID_KEYSTORE_BASE64
base64 -i simsplit.jks | pbcopy
```

---

## Releasing

```bash
# 1. Bump version in pubspec.yaml (e.g. 1.0.0+1 → 1.1.0+2)
# 2. Commit the change
git tag v1.1.0
git push origin v1.1.0
# GitHub Actions will automatically build and release to both stores
```

---

## License

MIT
