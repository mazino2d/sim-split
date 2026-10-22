---
name: release-manager
description: Plan, check and ship a SimSplit release to Google Play production (and later the App Store) — pick the CalVer version (YYYY.M.D), review what is in main since the last tag, walk the pre-release checklist (CI, e2e, Data safety, store listing, privacy policy, Firebase and App Check), bump pubspec.yaml, push the v-tag that runs release.yml, finish the draft release in Play Console and record it in the docs. Use when the user asks to "release", "ship", "go live", "lên production", "lên version mới", "tag a release", "promote to production", "what do I need before releasing", "release checklist", or invokes /release-manager. Not for internal/closed-test uploads of a branch (run build_android.yml manually) or for verifying a PR (e2e-tester).
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

## How a release flows

```
main ──► PR "chore(release): YYYY.M.D" (pubspec bump, docs, listing)  ──► merge
     ──► git tag vYYYY.M.D && git push origin vYYYY.M.D                  (user confirms)
     ──► release.yml: validate-version → build_android.yml (track: production,
         status: draft) → GitHub Release with the AAB
     ──► Play Console: release notes, review the draft, send for review, rollout
```

Pushing the tag builds **whatever `main` is at that commit** — check what is in it.
The store listing (`android/fastlane/metadata/`) and `docs/` go live on merge to
`main`, not on tag; see § Timing.

## 1. Plan — what ships

```bash
git fetch origin --tags --quiet
git describe --tags --abbrev=0 origin/main 2>/dev/null   # last tag, if any
git log --oneline <last-tag-or-production-commit>..origin/main
grep '^version:' pubspec.yaml
```

The production build before the first tag was promoted from closed testing, so
there may be no tag for it; then compare against the commit that build was made
from (ask the user, or read it from the Play Console release / GitHub Actions run).

Summarize for the user, grouped by user impact: new features, behaviour changes,
data or permission changes (sign-in, network, new SDKs — these drive Data safety),
DB schema bumps (migrations run on every upgraded device), and which roadmap
release / implementation phase this closes (`docs/product/roadmap.md`,
`docs/implementations/`). Draft the release notes (EN + VI, ≤ 500 chars each).

## 2. Preflight checklist

Run what can be run; list the rest as manual steps for the user.

| # | Gate | How | Who |
| --- | --- | --- | --- |
| 1 | CI green on the release commit | `gh run list --branch main --limit 5`; `pr_validate`, `codeql` passing | you |
| 2 | End-to-end | run the `e2e-tester` skill on `main`; for a Firebase release also on Android against the emulators | you |
| 3 | Upgrade path | the previous production version upgrades cleanly: Drift migration test from its schema, first sign-in uploads local data (R-3 AC7/AC8) | you |
| 4 | Store listing | EN and VI describe what the build does; `python3 scripts/play_metadata.py check` passes | you, via `docs-writer` |
| 5 | Privacy policy | `docs/privacy-policy.html` names the right versions and the data collected | you, via `docs-writer` |
| 6 | Data safety | Play Console → App content → Data safety matches the build (account name, email, user ID, user content; encrypted in transit; deletion via the app and the web) | user |
| 7 | App access | if sign-in is required, Play Console → App content → App access says so and how reviewers get in (any Google account) | user |
| 8 | Account deletion URL | an app with accounts must give Play a web link for deletion (Settings → Delete account on simsplit.web.app) | user |
| 9 | Signing fingerprints | Play App Signing SHA-1/SHA-256 are in Firebase (Google sign-in, Play Integrity) and in `assetlinks.json` (App Links); see everything-as-code `terraform/gcp/simsplit-as-se1-prd/_docs/setup.md` | user |
| 10 | Backend ready | Firestore rules and indexes deployed from `main` (`firebase_deploy`); budget and kill switch healthy | you check runs, user checks console |
| 11 | App Check | metrics show verified traffic on web; flip `app_check_enforced` in everything-as-code only when no installed build would be locked out | user approves the TF PR |
| 12 | Release workflow inputs | `release.yml` track `production`, status `draft` (default; the user rolls out in Play Console) | you |

Any red gate is a no-go; say which and what fixes it.

## 3. Release PR

On a branch `chore/release-YYYY.M.D`:

- `pubspec.yaml` → `version: YYYY.M.D+N`.
- Docs that name the upcoming version (implementation plan, roadmap row,
  `docs/product/index.md`, privacy policy) → the CalVer number. Use the `docs-writer`
  skill so every mirror changes together.
- Store listing changes, if the build changes what the app does.

Open it with the `pr-writer` skill, title `chore(release): YYYY.M.D`.

### Timing

Listing and `docs/` publish on merge, the build only after the tag and Play review.
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

If `validate-version` fails, the tag and pubspec disagree: delete the tag
(`git push origin :refs/tags/vYYYY.M.D`, with the user's OK), fix, re-tag.

Then the user, in Play Console → Production:

1. Open the draft release, paste the release notes (EN/VI).
2. Review → Send for review (managed publishing on: publish after approval).
3. Prefer a staged rollout (e.g. 20 % → 50 % → 100 %) for releases that change
   data or sign-in; watch Android vitals (crashes, ANRs) between steps.

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
- Production releases are uploaded as `draft`; nothing reaches users until the user
  sends it for review in Play Console.
- Play rejects concurrent edits: don't run `build_android.yml` manually while
  `release.yml` is uploading.
- Only `main` and `v*` tags can authenticate to Play (Workload Identity in
  everything-as-code), so a release from another branch fails at upload.
- iOS is not in `release.yml` yet (R-3 P8); say so when the user asks for "all
  platforms".
