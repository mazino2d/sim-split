# Dev environment — implementation plan

Status: in progress (app and CI ready; waiting for infrastructure)   ·   Spec: none (engineering change)   ·   Written 2026-10-24

Until now every merge to `main` shipped straight to production: the web app at
`simsplit.web.app`, Firestore rules and indexes, and an internal-track build of the
production Play app. This plan adds a dev environment so `main` ships to dev and only
tags reach production. Work spans this repo and `everything-as-code` (infrastructure).

## Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Environments | Two: **dev** (`simsplit-as-se1-dev`) and **prd** (`simsplit-as-se1-prd`, unchanged) | One place to try `main` against real Firebase without touching users' data. |
| What ships where | Push to `main` → dev (Android internal track of SimSplit [Dev], web at `simsplit-as-se1-dev.web.app`, rules and indexes). `vYYYY.M.D-rc.N` → prd Play closed testing. `vYYYY.M.D` → prd Play production, web, rules and indexes | Production changes only through a reviewed release tag. |
| Selecting the environment in Dart | `--dart-define=APP_ENV=dev\|prd`, default `prd`, read once in `lib/core/constants/app_env.dart`; an unknown value throws | A build without the define behaves exactly as before. A typo fails at start-up instead of silently talking to the wrong backend. |
| Per-environment values | Firebase options (`firebase_options.dart` / `firebase_options_dev.dart`), Google sign-in server client ID, web origin (invite links) switch on `appEnv`; the reCAPTCHA site key and telemetry URL stay `--dart-define`s that CI fills per environment | One switch per value, next to the value; nothing else hardcodes a project, package or domain. |
| Android | Product flavors `dev` (`applicationIdSuffix ".dev"`, label "SimSplit [Dev]", App Link host `simsplit-as-se1-dev.web.app`) and `prd`; both sign with the same upload key | A separate Play app keeps dev builds away from production testers and lets both be installed side by side. |
| `google-services.json` | None, per flavor or otherwise | The app never used it: Firebase is initialised from the Dart options and the Google Services Gradle plugin is not applied. Adding placeholder JSON files would be dead config. |
| iOS | Out of scope; builds as today against prd. `DevFirebaseOptions` has no iOS app, so an iOS build with `APP_ENV=dev` runs local-only | No Apple Developer account (R-3 P8). |
| Telemetry | Per environment: dev builds send to the `telemetry` endpoint in `simsplit-as-se1-dev`, which writes to `dataplatform-as-se1-dev`; `telemetry_deploy.yml` deploys it from `main` (prd from release tags) | Each endpoint only accepts its own project's App Check tokens; dev data lands in the dev warehouse, so data-platform can be built and tested on it while prd stays clean. (Until 2026-10-27 dev builds sent nothing.) |
| App Links on the dev site | `firebase/hosting/dev/` is copied over `build/web/` before a dev deploy; it holds the dev `assetlinks.json` | `web/` stays the prd source; the override is explicit and small. |
| Prd web deploy | `release.yml` calls `firebase_deploy.yml` with `environment: prd` after the Android build and upload succeeded; a manual run always deploys dev | A mistyped tag or a failed upload can't deploy the web app, and no other path (e.g. a release-candidate tag) reaches prd. |
| Dev Firebase config | `lib/firebase_options_dev.dart` is committed, generated from the Firebase Management API like `lib/firebase_options.dart` | Same approach as prd; no `google-services.json` or Gradle plugin. |

## Phases

| Phase | Repo | Scope | Effort (days) |
| --- | --- | --- | --- |
| P1 | sim-split | This change: `APP_ENV`, dev Firebase options (placeholders), flavors, dev Hosting overrides, `.firebaserc` alias and target, CI split (`build_android`, `firebase_deploy`, `release`), docs | 1 |
| P2 | everything-as-code | Stack `terraform/gcp/simsplit-as-se1-dev`: project, Firebase (Android app `com.mazino2d.simsplit.dev`, Web app, Hosting site `simsplit-as-se1-dev` (the default site; `simsplit-dev` is taken)), Auth with Google, Firestore, App Check (Play Integrity, reCAPTCHA Enterprise key), WIF for this repo and the deployer account; repo variables `DEV_GCP_WORKLOAD_IDENTITY_PROVIDER`, `DEV_GCP_SERVICE_ACCOUNT`, `DEV_FIREBASE_PROJECT`, `DEV_RECAPTCHA_ENTERPRISE_SITE_KEY` (later replaced by the `dev` and `prd` GitHub Environments' variables: `FIREBASE_PROJECT`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_FIREBASE_DEPLOYER`, `RECAPTCHA_ENTERPRISE_SITE_KEY`, `TELEMETRY_URL`) | 1 |
| P3 | sim-split | Fill the placeholders (below) from P2's outputs and the Play app; first dev deploy and internal build | 0.5 |

## Manual steps (no API or Terraform support)

1. Create the Play app "SimSplit [Dev]" (`com.mazino2d.simsplit.dev`) in Play Console,
   upload the first AAB by hand (the API can't create an app or its first release),
   and set up the internal testing track and testers.
2. Invite `gha-play-publisher@simsplit-as-se1-prd.iam.gserviceaccount.com` to SimSplit
   Dev with the release permissions (Play Console → Users and permissions).
3. Copy the dev app's Play App Signing and upload key SHA-256 into
   `firebase/hosting/dev/.well-known/assetlinks.json`, and the SHA-1/SHA-256 into the
   dev Firebase Android app (Google sign-in, Play Integrity).

## Risks

- Until P2 is applied and its repo variables exist, the dev `firebase_deploy` run on
  every push to `main` fails at authentication, and the dev `build_android` upload
  fails until the Play app exists. Production is not affected.
- A new Firestore index now reaches prd only with the release tag. An app that needs
  it waits for the index to build after the release.
- The GitHub Release asset is now `app-prd-release.aab` (was `app-release.aab`).
