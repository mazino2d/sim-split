# CI/CD

| Workflow | Trigger | Result |
| --- | --- | --- |
| `pr_validate` | Every PR → `main` | Parallel format/analyze/test, store-metadata check and actionlint, each skipped unless its files change; required check: `PR Validation` |
| `build_android` | Push → `main` touching `lib/**`, `android/**`, `assets/**` or `pubspec.lock`; manual; or called by `release` | AAB → Play Store; on push to the `internal` track as completed (testers get it at once), manual defaults to `internal` draft |
| `build_ios` | Manual | Unsigned iOS build (signing disabled until the Apple account is active) |
| `release` | Push a `vX.Y.Z` tag | Validates the tag against `pubspec.yaml`, uploads the AAB to the Play `production` track with the release notes in `android/fastlane/whatsnew/` as an inProgress release at 20 % (sent for review on upload), creates a GitHub Release |
| `play_rollout` | Manual, from `main` | Shows, widens (50 %, 100 %), halts or resumes the staged production rollout (`scripts/play_rollout.py`) |
| `firebase_deploy` | Push → `main` touching `firebase.json`, `.firebaserc`, `firebase/**` (not `firebase/test/**`), the app (`lib/`, `web/`, `assets/`, `pubspec.*`, `l10n.yaml`) or the workflow itself, or manual | Builds the web app and deploys it with Firestore rules and indexes to `simsplit-as-se1-prd` (keyless WIF) |
| `play_metadata` | Push → `main` touching `android/fastlane/metadata/**`, or manual (dry run) | Syncs Play store listing, images, contact, Data safety (see `android/fastlane/README.md`) |
| `pages` | Push → `main` touching `docs/**`, or manual; PRs build only | Jekyll build of `docs/` deployed to GitHub Pages (landing page, privacy policy linked from Play) |
| `codeql` | Push/PR touching `.github/**`, weekly | CodeQL scan of the workflows |

Shared logic comes from [mazino2d/github-workflows](https://github.com/mazino2d/github-workflows) (`@v1`): `pages`, `codeql` and the actionlint job of `pr_validate` call its reusable workflows, and `.github/actions/flutter-setup` pins the Flutter version for its shared `flutter-setup` action.

`pr_validate` also runs a **Firestore rules** job when `firebase/**` changes:
`npm ci --prefix firebase/test`, then
`npx firebase-tools@14 emulators:exec --only firestore --project demo-simsplit "npm --prefix firebase/test test"`
(needs Java). Every rules change needs a test in `firebase/test/`.

Release tags must match the `version` in `pubspec.yaml`.
