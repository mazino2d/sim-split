# CI/CD

| Workflow | Trigger | Result |
| --- | --- | --- |
| `pr_validate` | Every PR → `main` | Parallel format/analyze/test, store-metadata check, Firestore rules tests, telemetry endpoint tests and actionlint, each skipped unless its files change; required check: `PR Validation` |
| `build_android` | Push → `main` touching `lib/**`, `android/**` (not `android/fastlane/**`), `assets/**` or `pubspec.lock`; manual; or called by `release` / `release_candidate` | AAB → Play Store. Push and manual runs: `--flavor dev`, `APP_ENV=dev`, no telemetry, to `com.mazino2d.simsplit.dev` (SimSplit Dev); on push to `internal` as completed with versionName `YYYY.M.D-dev.<sha7>`, manual defaults to `internal` draft. Called with a `release_tag`: `--flavor prd`, `APP_ENV=prd`, `TELEMETRY_URL`, to `com.mazino2d.simsplit` |
| `build_ios` | Manual | Unsigned iOS build (signing disabled until the Apple account is active) |
| `release_candidate` | Push a `vYYYY.M.D-rc.N` tag | Validates the tag format, uploads the AAB as `YYYY.M.D-rc.N` with the `whatsnew/` notes to the `alpha` (closed testing) track, creates a GitHub pre-release |
| `release` | Push a `vYYYY.M.D` tag | Validates the tag against `pubspec.yaml`, uploads the AAB to the Play `production` track with the release notes in `android/fastlane/whatsnew/` as an inProgress release at 20 % (sent for review on upload), calls `firebase_deploy` for prd, creates a GitHub Release |
| `play_rollout` | Manual, from `main` | Shows, widens (50 %, 100 %), halts or resumes the staged production rollout (`scripts/play_rollout.py`) |
| `firebase_deploy` | Push → `main` touching `firebase.json`, `.firebaserc`, `firebase/**` (not `firebase/test/**`), the app (`lib/`, `web/`, `assets/`, `pubspec.*`, `l10n.yaml`) or the workflow itself; manual; or called by `release` | Builds the web app (`APP_ENV` of the target) and deploys it with Firestore rules and indexes. Push and manual runs on a branch: dev (`vars.DEV_FIREBASE_PROJECT`, site `simsplit-as-se1-dev`, WIF from `vars.DEV_GCP_WORKLOAD_IDENTITY_PROVIDER` / `vars.DEV_GCP_SERVICE_ACCOUNT`, reCAPTCHA key `vars.DEV_RECAPTCHA_ENTERPRISE_SITE_KEY`, `firebase/hosting/dev/` copied over `build/web/`). From `release` or a manual run on a `vYYYY.M.D` tag: prd (`simsplit-as-se1-prd`, keyless WIF) |
| `telemetry_deploy` | Push → `main` touching `services/telemetry/**` (not its tests) or the workflow, or manual | Builds the R-4 telemetry endpoint image, pushes it to Artifact Registry and deploys it to the Cloud Run service `telemetry` in `simsplit-as-se1-prd` (keyless WIF as `gha-telemetry-deployer`); only the image changes |
| `play_metadata` | PR touching `android/fastlane/metadata/android/**` (dry-run plan as a PR comment); push → `main` touching that, `scripts/play_metadata.py` or the workflow; manual (dry run by default) | Syncs listing, images, contact; uploads `data_safety.csv` when it changed (see `android/fastlane/README.md`) |
| `pages` | Push → `main` touching `docs/**`, or manual; PRs build only | Jekyll build of `docs/` deployed to GitHub Pages (landing page, privacy policy linked from Play) |
| `codeql` | Push/PR → `main` touching `.github/workflows/**` or `.github/actions/**`, weekly | CodeQL scan of the workflows |

Shared logic comes from [mazino2d/github-workflows](https://github.com/mazino2d/github-workflows) (`@v1`): `pages`, `codeql` and the actionlint job of `pr_validate` call its reusable workflows, and `.github/actions/flutter-setup` pins the Flutter version for its shared `flutter-setup` action.

`pr_validate` also runs a **Firestore rules** job when `firebase/**` changes:
`npm ci --prefix firebase/test`, then
`npx firebase-tools@14 emulators:exec --only firestore --project demo-simsplit "npm --prefix firebase/test test"`
(needs Java). Every rules change needs a test in `firebase/test/`.

Production tags (`vYYYY.M.D`) must match the `version` in `pubspec.yaml`; RC tags are only format-checked.
