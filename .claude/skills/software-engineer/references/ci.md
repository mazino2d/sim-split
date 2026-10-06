# CI/CD

| Workflow | Trigger | Result |
| --- | --- | --- |
| `pr_validate` | Every PR → `main` | Parallel format/analyze/test, store-metadata check and actionlint, each skipped unless its files change; required check: `PR Validation` |
| `build_android` | Manual, or called by `release` | AAB → Play Store (internal track by default) |
| `build_ios` | Manual | Unsigned iOS build (signing disabled until the Apple account is active) |
| `release` | Push a `vX.Y.Z` tag | Validates the tag against `pubspec.yaml`, uploads the AAB to the Play `production` track as a draft, creates a GitHub Release |
| `firebase_deploy` | Push → `main` touching `firebase.json`, `.firebaserc`, `firebase/**` (not `firebase/test/**`), the app (`lib/`, `web/`, `assets/`, `pubspec.*`, `l10n.yaml`) or the workflow itself, or manual | Builds the web app and deploys it with Firestore rules and indexes to `simsplit-as-se1-prd` (keyless WIF) |
| `play_metadata` | Push → `main` touching `android/fastlane/metadata/**`, or manual (dry run) | Syncs Play store listing, images, contact, Data safety (see `android/fastlane/README.md`) |

`pr_validate` also runs a **Firestore rules** job when `firebase/**` changes:
`npm ci --prefix firebase/test`, then
`npx firebase-tools@14 emulators:exec --only firestore --project demo-simsplit "npm --prefix firebase/test test"`
(needs Java). Every rules change needs a test in `firebase/test/`.

Release tags must match the `version` in `pubspec.yaml`.
