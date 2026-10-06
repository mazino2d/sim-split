# CI/CD

| Workflow | Trigger | Result |
| --- | --- | --- |
| `pr_validate` | Every PR → `main` | Parallel format/analyze/test, store-metadata check and actionlint, each skipped unless its files change; required check: `PR Validation` |
| `build_android` | Manual, or called by `release` | AAB → Play Store (internal track by default) |
| `build_ios` | Manual | Unsigned iOS build (signing disabled until the Apple account is active) |
| `release` | `git tag v1.0.0` | Production release to both stores |
| `firebase_deploy` | Push → `main` touching `firebase.json`, `.firebaserc` or `firebase/**` (not `firebase/test/**`), or manual | Deploys Firestore rules, indexes and Hosting to `simsplit-as-se1-prd` (keyless WIF) |
| `play_metadata` | Push → `main` touching `android/fastlane/metadata/**`, or manual (dry run) | Syncs Play store listing, images, contact, Data safety (see `android/fastlane/README.md`) |

`pr_validate` also runs a **Firestore rules** job when `firebase/**` changes:
`npm ci --prefix firebase/test`, then
`npx firebase-tools@14 emulators:exec --only firestore --project demo-simsplit "npm --prefix firebase/test test"`
(needs Java). Every rules change needs a test in `firebase/test/`.

Release tags must match the `version` in `pubspec.yaml`.
