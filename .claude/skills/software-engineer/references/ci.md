# CI/CD

| Workflow | Trigger | Result |
| --- | --- | --- |
| `pr_validate` | Every PR → `main` | Parallel format/analyze/test, store-metadata check, Firestore rules tests, telemetry endpoint tests and actionlint, each skipped unless its files change; required check: `PR Validation` |
| `build_android` | Push → `main` touching `lib/**`, `android/**` (not `android/fastlane/**`), `assets/**`, `l10n.yaml`, `pubspec.lock`, `.github/actions/flutter-setup/**` or the workflow itself; manual (from `main`); or called by `release` / `release_candidate` | AAB → Play Store. Push and manual runs (environment `dev`): `--flavor dev`, `APP_ENV=dev`, no telemetry, to `com.mazino2d.simsplit.dev` (SimSplit [Dev]); on push to `internal` as completed with versionName `YYYY.M.D-dev.<sha7>`, manual defaults to `internal` draft. Called with a `release_tag` (environment `prd`, waits for approval): `--flavor prd`, `APP_ENV=prd`, `TELEMETRY_URL`, to `com.mazino2d.simsplit` |
| `build_ios` | Manual | Unsigned iOS build (signing disabled until the Apple account is active) |
| `release_candidate` | Push a `vYYYY.M.D-rc.N` tag | Validates the tag format, after approval (`prd`) uploads the AAB as `YYYY.M.D-rc.N` with the `whatsnew/` notes to the `alpha` (closed testing) track, creates a GitHub pre-release |
| `release` | Push a `vYYYY.M.D` tag | Validates the tag against `pubspec.yaml`, uploads the AAB to the Play `production` track with the release notes in `android/fastlane/whatsnew/` as a completed release at 100 % (sent for review on upload), then calls `firebase_deploy` for prd, calls `telemetry_deploy` (after the tag check, alongside the upload), creates a GitHub Release; the upload and both deploys each wait for approval (`prd`) |
| `play_rollout` | Manual, from `main` (environment `store`) | Shows, widens (50 %, 100 %), halts or resumes the staged production rollout (`scripts/play_rollout.py`) |
| `firebase_deploy` | Push → `main` touching `firebase.json`, `.firebaserc`, `firebase/**` (not `firebase/test/**`), the app (`lib/`, `web/`, `assets/`, `pubspec.*`, `l10n.yaml`) or the workflow itself; manual; or called by `release` | Builds the web app (`APP_ENV` of the target) and deploys it with Firestore rules and indexes, reading `FIREBASE_PROJECT`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_FIREBASE_DEPLOYER`, `RECAPTCHA_ENTERPRISE_SITE_KEY` and (prd) `TELEMETRY_URL` from the environment's variables. Push and manual runs (from `main`): dev, `firebase/hosting/dev/` copied over `build/web/`, then a smoke test of the live site (HTTP 200, `assetlinks.json` names `com.mazino2d.simsplit.dev`, `scripts/smoke_web.sh <url>` in headless Chromium). prd only when `release` calls it for a `vYYYY.M.D` tag |
| `telemetry_deploy` | Called by `release`; manual from a `vYYYY.M.D` tag | Environment `prd` (waits for approval), checks the tag is exactly `vYYYY.M.D`, builds the R-4 telemetry endpoint image, pushes it to Artifact Registry and deploys it to the Cloud Run service `telemetry` in `simsplit-as-se1-prd` (keyless WIF as `gha-telemetry-deployer`); only the image changes. Merges to `main` don't deploy it; `pr_validate` tests it |
| `play_metadata` | Environment `store`. PR touching `android/fastlane/metadata/android/**` (dry-run plan as a PR comment); push → `main` touching that, `scripts/play_metadata.py` or the workflow; manual from `main` (dry run by default) | Syncs listing, images, contact; uploads `data_safety.csv` when it changed in the push (`before..HEAD`); one job per app, prd and dev (`--env dev`: same listing, title from `play.json` → `dev`) (see `android/fastlane/README.md`) |
| `pages` | Push → `main` touching `docs/**`, or manual; PRs build only | Jekyll build of `docs/` deployed to GitHub Pages (landing page, privacy policy linked from Play) |
| `codeql` | Push/PR → `main` touching `.github/workflows/**` or `.github/actions/**`, weekly | CodeQL scan of the workflows |

Jobs that authenticate to Google Cloud run in a GitHub Environment, managed in
mazino2d/everything-as-code: **`dev`** (`main` only), **`prd`** (`v*` tags only;
the maintainer approves every job) and **`store`** (`main` only; Play listing and
rollout). `dev` and `prd` hold the same variable names, so a job reads
`vars.FIREBASE_PROJECT` and gets its environment's value. The Play publisher
account (`gha-play-publisher@simsplit-as-se1-prd`) stays hard-coded in the
workflows. Workload Identity admits only `main` and `v*` tags as well.
`firebase_deploy` fails before building if `FIREBASE_PROJECT` is unset or isn't the
environment's project (`simsplit-as-se1-dev` / `-prd`), since firebase-tools would
otherwise fall back to the `.firebaserc` default (prd).

Play rejects concurrent edits on one app, so every job that edits a Play app
(`build_android`, `play_metadata` apply, `play_rollout`) joins one job-level
concurrency group per package, `play-com.mazino2d.simsplit` or
`play-com.mazino2d.simsplit.dev`, never cancelled in progress. GitHub keeps only the
newest pending job per group, so a queued job can be replaced by a newer one.

Third-party actions are pinned to a commit SHA with a `# vX.Y.Z` comment
(Dependabot bumps both); `firebase-tools` is pinned to an exact version.

Shared logic comes from [mazino2d/github-workflows](https://github.com/mazino2d/github-workflows) (`@v1`): `pages`, `codeql` and the actionlint job of `pr_validate` call its reusable workflows, and `.github/actions/flutter-setup` pins the Flutter version for its shared `flutter-setup` action.

`pr_validate` also runs a **Firestore rules** job when `firebase/**` changes:
`npm ci --prefix firebase/test`, then
`npx firebase-tools@14.27.0 emulators:exec --only firestore --project demo-simsplit "npm --prefix firebase/test test"`
(needs Java). Every rules change needs a test in `firebase/test/`.

Production tags (`vYYYY.M.D`) must match the `version` in `pubspec.yaml`; RC tags are only format-checked.
