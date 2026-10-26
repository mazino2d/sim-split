---
name: release-manager
description: Plan, check and ship a SimSplit release to Google Play production (and later the App Store) — pick the CalVer version (YYYY.M.D), review what is in main since the last tag, walk the pre-release checklist (CI, e2e, Data safety, store listing, privacy policy, Firebase and App Check), bump pubspec.yaml, push the v-tag that runs release.yml (release notes, 20 % staged rollout sent for review), widen the rollout with play_rollout.yml and record it in the docs. Use when the user asks to "release", "ship", "go live", "lên production", "lên version mới", "tag a release", "promote to production", "what do I need before releasing", "release checklist", or invokes /release-manager. Not for internal-test uploads (every app-code merge to main uploads one to the separate SimSplit [Dev] app; other branches: run build_android.yml manually) or for verifying a PR (e2e-tester).
argument-hint: "[plan|preflight|ship|post] [YYYY.M.D]"
allowed-tools: Read, Edit, Write, Grep, Glob, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(flutter:*), Bash(dart:*), Bash(python3 scripts/play_metadata.py check), Bash(python3 .claude/skills/docs-writer/scripts/*)
---

# SimSplit release manager

A release is the most outward-facing thing in this repo: it reaches every
installed device and cannot be pulled back once users update. Your job is to make
the release boring — know exactly what ships, check every gate, and leave the
irreversible steps (pushing the tag, sending for review, rollout) to the user's
explicit go-ahead.

Report a checklist with a status per item, not a log. Never mark an item done that
you did not check; say what is manual and who has to do it.

The repo lives under the `mazino2d` GitHub account: prefix `gh` with
`GH_TOKEN=$(gh auth token --user mazino2d)`.

## Version scheme

Releases use **CalVer `YYYY.M.D`** of the day the tag is pushed, e.g. `2026.10.22`.

- No zero padding (`2026.11.5`, not `2026.11.05`): the version must stay valid
  semver, which forbids leading zeros, because pubspec and `release.yml` treat it as
  `X.Y.Z`.
- pubspec: `version: 2026.10.22+N`. The `+N` is ignored in CI — `build_android.yml`
  overrides the versionCode with minutes since 2026-01-01 UTC, so it always
  increases. Bump `N` by one anyway so local builds differ.
- Tag: `v2026.10.22`. It matches the `v[0-9]+.[0-9]+.[0-9]+` filter in
  `release.yml`, and `validate-version` fails the run if it differs from pubspec.
- One production release per day. A same-day hotfix takes the next day's date.
- The last semver release is `1.0.0` (the offline R-2 build). Everything after it is
  CalVer; Play only compares versionCodes, so the jump from 1.0.0 is fine.

Every build gets a versionName that says what it is (`build_android.yml` passes
`--build-name`; pubspec only has to match production tags):

| Build | Trigger | versionName | Play app | Play track |
| --- | --- | --- | --- | --- |
| Dev | merge to `main` touching app code, or a manual run | `YYYY.M.D-dev.<sha7>` (build date, UTC) | SimSplit [Dev] (`com.mazino2d.simsplit.dev`, `simsplit-as-se1-dev`) | internal |
| Release candidate | tag `vYYYY.M.D-rc.N` (`release_candidate.yml`) | `YYYY.M.D-rc.N` | SimSplit (`com.mazino2d.simsplit`, `simsplit-as-se1-prd`) | closed testing (`alpha`) |
| Production | tag `vYYYY.M.D` (`release.yml`) | `YYYY.M.D` | SimSplit | production, 20 % |

The web app, Firestore rules and indexes follow the same split: `main` deploys them
to dev (`simsplit-as-se1-dev.web.app`), and only the production tag deploys them to prd
(`simsplit.web.app`), from `release.yml`.

An RC's date is the day it is cut and N counts that day's candidates from 1; it
does not need to match pubspec or the later production date. RC builds carry the
`whatsnew/` notes and a GitHub pre-release.

## How a release flows

```
main ──► PR "chore(release): YYYY.M.D" (pubspec bump, whatsnew, docs, listing) ──► merge
     ──► git tag vYYYY.M.D && git push origin vYYYY.M.D                  (user confirms)
     ──► release.yml: validate-version → build_android.yml (--flavor prd, track:
         production, status: inProgress, 20 %, notes from android/fastlane/whatsnew/)
         → sent for review → GitHub Release with the AAB
                                         → firebase_deploy.yml (prd: web app at
         simsplit.web.app, Firestore rules and indexes)
         each prd job waits for approval in the prd environment     (user approves)
     ──► approved: live for 20 % (managed publishing is off)
     ──► play_rollout.yml: 50 % → 100 % after checking Android vitals  (user confirms)
```

Pushing the tag builds **whatever `main` is at that commit** — check what is in it.
The store listing (`android/fastlane/metadata/`) and `docs/` go live on merge to
`main`, not on tag; see § Timing.

## 1. Plan — what ships

```bash
git fetch origin --tags --quiet
git describe --tags --abbrev=0 --exclude='*-rc.*' origin/main   # last production tag
git log --oneline <last-tag>..origin/main
grep '^version:' pubspec.yaml
```

Summarize for the user, grouped by user impact: new features, behaviour changes,
data or permission changes (sign-in, network, new SDKs — these drive Data safety),
DB schema bumps (migrations run on every upgraded device), and which roadmap
release / implementation phase this closes (`docs/product/roadmap.md`,
`docs/implementations/`). Draft the release notes (EN + VI, ≤ 500 chars each) for
`android/fastlane/whatsnew/whatsnew-{en-US,vi}`.

## 2. Preflight checklist

Run what can be run; list the rest as manual steps for the user.

| # | Gate | How | Who |
| --- | --- | --- | --- |
| 1 | CI green on the release commit | the release PR's checks passed (`gh pr checks <n>`, required `PR Validation`); `gh run list --branch main --limit 5` shows the push runs green | you |
| 2 | End-to-end | run the `e2e-tester` skill on `main`; for a Firebase release also on Android against the emulators | you |
| 3 | Upgrade path | the previous production version upgrades cleanly: Drift migration test from its schema, first sign-in uploads local data (R-3 AC7/AC8) | you |
| 4 | Store listing | EN and VI describe what the build does; `python3 scripts/play_metadata.py check` passes | you, via `docs-writer` |
| 5 | Privacy policy | `docs/privacy-policy.html` names the right versions and the data collected | you, via `docs-writer` |
| 6 | Data safety | `android/fastlane/metadata/android/data_safety.csv` matches the build (account name, email, user ID, user content; encrypted in transit; deletion via the app and the web); `play_metadata.yml` uploads it on merge | you |
| 7 | Sign in details | if sign-in is required, Play Console → App content → Sign in details (was App access) says so and how reviewers get in (any Google account); no API | user |
| 8 | Account deletion URL | `PSL_ACCOUNT_DELETION_URL` in `data_safety.csv` points at `privacy-policy.html#delete` | you |
| 9 | Signing fingerprints | Play App Signing SHA-1/SHA-256 are in Firebase (Google sign-in, Play Integrity) and in `assetlinks.json` (App Links); see everything-as-code `terraform/gcp/simsplit-as-se1-prd/_docs/setup.md` | user |
| 10 | Backend ready | the rules and indexes on `main` deployed cleanly to dev (`firebase_deploy` push runs green); the tag deploys them to prd, so a new index must build before the app needs it; budget and kill switch healthy | you check runs, user checks console |
| 11 | App Check | still enforced (`app_check_enforced = true` in everything-as-code); App Check metrics show verified traffic on Android and web | user checks console |
| 12 | Release notes | `whatsnew/whatsnew-{en-US,vi}` describe this release; `python3 scripts/play_metadata.py check` passes | you |

Any red gate is a no-go; say which and what fixes it.

## 3. Release PR

On a branch `chore/release-YYYY.M.D`:

- `pubspec.yaml` → `version: YYYY.M.D+N`.
- `android/fastlane/whatsnew/whatsnew-{en-US,vi}` → this release's notes.
- Docs that name the upcoming version (implementation plan, roadmap row,
  `docs/product/index.md`, privacy policy) → the CalVer number. Use the `docs-writer`
  skill so every mirror changes together.
- Store listing changes, if the build changes what the app does.

Open it with the `pr-writer` skill, title `chore(release): YYYY.M.D`.

### Timing

Listing, Data safety and `docs/` publish on merge (listing changes after Play's
review; managed publishing is off), the build only after the tag and Play review.
If the release changes what the app does (e.g. offline → sign-in), merging early
makes the listing describe a build users can't get yet. Merge the release PR and
push the tag the same day, and tell the user the listing is live before the build
is approved.

## 4. Ship (irreversible — ask first)

Show the user the commit, version and checklist, and wait for an explicit yes. Then:

```bash
git switch main && git pull --ff-only
grep '^version:' pubspec.yaml               # must be YYYY.M.D+N
git tag -a vYYYY.M.D -m "SimSplit YYYY.M.D"
git push origin vYYYY.M.D
GH_TOKEN=$(gh auth token --user mazino2d) gh run watch \
  $(GH_TOKEN=$(gh auth token --user mazino2d) gh run list --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')
```

Every job in the `prd` GitHub Environment (the Android upload, then the Firebase
deploy) waits for the maintainer's approval: tell the user to approve it in the run
(**Review deployments**) or with
`gh api -X POST repos/mazino2d/sim-split/actions/runs/<run-id>/pending_deployments`
(`-f 'environment_ids[]=<id>' -f state=approved -f comment=…`). The Firebase deploy
starts only after the upload succeeded. Release candidates (`-rc.N` tags) wait for
approval the same way.

If `validate-version` fails, the tag and pubspec disagree: delete the tag
(`git push origin :refs/tags/vYYYY.M.D`, with the user's OK), fix, re-tag.

The upload goes to Play review by itself and reaches 20 % of users when approved;
nothing to do in Play Console. Then, one step at a time and only on the user's yes
after they checked Android vitals (crashes, ANRs):

```bash
GH_TOKEN=$(gh auth token --user mazino2d) gh workflow run play_rollout.yml -f action=status
GH_TOKEN=$(gh auth token --user mazino2d) gh workflow run play_rollout.yml -f action=50%
GH_TOKEN=$(gh auth token --user mazino2d) gh workflow run play_rollout.yml -f action=100%
# bad vitals: -f action=halt (users who have it keep it), later -f action=resume
```

## 5. Post-release

- Release live → update the roadmap / implementation plan status (`product-owner`,
  `docs-writer`), and the landing page if it names the version.
- Check the GitHub Release `SimSplit vYYYY.M.D` has the AAB.
- Watch Firebase usage and budget for the first days after a backend-facing
  release.
- Write down anything that went wrong as a new pitfall below.

## Known pitfalls

- `release.yml` builds the tag's commit, not a closed-test build. To ship a build that
  is already in testing, promote it in Play Console instead of tagging.
- Pushing the tag sends the build for review with no draft step: everything that
  must be right (notes, listing, Data safety) has to be on `main` before the tag.
- Play rejects concurrent edits to the same app. Merges to `main` upload to SimSplit
  Dev, a separate app, so they no longer race a tag; don't run `play_rollout.yml`
  while `release.yml` is uploading.
- Only `main` and `v*` tags can authenticate to Play (Workload Identity in
  everything-as-code), so a release from another branch fails at upload. The
  GitHub Environments enforce the same: `prd` admits `v*` tags only, `dev` and
  `store` (`play_rollout.yml`, `play_metadata.yml`) admit `main` only.
- A manual `firebase_deploy.yml` run always deploys dev; prd web, rules and
  indexes ship only through `release.yml`. To redeploy prd, re-run the failed
  jobs of the release run.
- iOS is not in `release.yml` yet (R-3 P8); say so when the user asks for "all
  platforms".
