---
name: pr-writer
description: Draft and open a GitHub pull request for the SimSplit repo (mazino2d/sim-split). Use whenever the user asks to "write a PR", "open/create a PR", "tạo PR", "push and open a PR", "draft a PR description", or "/pr-writer" — including at the end of any coding task in this repo when the user wants the work submitted. Reviews the branch diff against Clean Architecture rules, runs the same checks as CI, writes an English title and body, and creates the PR with gh.
argument-hint: "[base-branch] [--draft]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(flutter pub get:*), Bash(dart run build_runner:*), Bash(flutter gen-l10n:*), Bash(flutter analyze:*), Bash(dart format:*), Bash(flutter test:*), Bash(python3 .claude/skills/docs-writer/scripts/check_docs.py*), Bash(python3 scripts/play_metadata.py check), Bash(npm ci --prefix firebase/test), Bash(npm ci --prefix services/telemetry), Bash(npm --prefix services/telemetry run typecheck), Bash(npm --prefix services/telemetry test), Bash(npx firebase-tools@14 emulators:exec --only firestore --project demo-simsplit:*)
---

# Write a SimSplit pull request

Everything in the PR — title, body, commit messages — is **English** (see `AGENTS.md` § Language policy).

## 1. Gather context

Base branch is `$ARGUMENTS`'s first word if given, otherwise `main`. Pass `--draft` to `gh pr create` if `--draft` is in the arguments.

```bash
git status --short
git branch --show-current
git fetch origin <base> --quiet
git log --oneline origin/<base>..HEAD
git diff --stat origin/<base>...HEAD
git diff origin/<base>...HEAD
gh pr view --json url,state 2>/dev/null   # an open PR already exists → offer to update its body instead
```

- On `main` with changes: create a branch first (`feat/…`, `fix/…`, `chore/…`, `refactor/…`).
- Uncommitted changes: ask whether to commit them (Conventional Commit message) before continuing.
- Read the diff fully — the description must come from what the code actually does, not just commit subjects.

## 2. Review the diff against repo rules

The rules are explained in the `software-engineer` skill (`../software-engineer/references/`); this is the checklist.

Flag every violation in the PR's **Notes for reviewers** section (or fix it first if the user agrees):

| Check | How |
| --- | --- |
| Domain stays pure Dart | No `package:flutter`, `drift`, `firebase_*`, `cloud_firestore`, `riverpod`, `go_router` imports under `lib/domain/` |
| Presentation doesn't touch data | No Drift/DAO/mapper/table imports under `lib/presentation/` |
| Money is `int` cents | No new `double` amounts; fields named `*Cents` |
| Errors use `Either<Failure, T>` | No bare `throw` in domain/data |
| `group.members` not used | Use `memberListProvider(groupId)` |
| Localization | New strings added to **both** `app_en.arb` and `app_vi.arb`, English camelCase keys |
| Generated files | No hand edits to `*.g.dart` / `*.freezed.dart`; codegen re-run if models/DAOs/providers changed |
| Secrets | No `android/key.properties`, `*.jks`, `AuthKey_*.p8` in the diff |
| Tests | New/changed use cases have Mocktail tests; repositories use in-memory Drift |
| Docs in sync | Behaviour, commands, workflows or data collected changed → the mirrors in `../docs-writer/references/doc-map.md` changed too (run `docs-writer` sync if not); `python3 .claude/skills/docs-writer/scripts/check_docs.py` passes |
| Sync | New synced fields go through `SyncCodec` and `SyncRecorder`; `firebase/firestore.rules` changes come with a test in `firebase/test/` |

```bash
git diff origin/<base>...HEAD --name-only | grep '^lib/domain/' | xargs -r grep -nE "package:(flutter|drift|firebase_[a-z]+|cloud_firestore|riverpod|flutter_riverpod|go_router)/"
git diff origin/<base>...HEAD -U0 | grep -nE '^\+.*\bdouble\b'
git diff origin/<base>...HEAD -U0 | grep -nE '^\+.*\.members\b'
```

## 3. Run CI checks locally

Run every job of `.github/workflows/pr_validate.yml` whose paths the diff touches. The jobs, their path filters and their local commands are listed once, in `AGENTS.md` § What CI runs on every PR — read it there; don't work from memory. Docs-only PRs skip them all. The format check covers the whole repo, so pre-existing issues on the base branch fail CI too.

For the Dart jobs, resolve packages and regenerate code first. Without `pub get`, `dart format` can't read the package language version and reformats far more files than CI does.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

Report results honestly. If something fails, show the output and ask whether to fix it or open the PR anyway (then list the failure under Notes for reviewers).

## 4. Write the title

Conventional Commits, imperative, ≤ 72 chars, no trailing period:

`<type>(<optional scope>): <summary>` — types: `feat`, `fix`, `refactor`, `chore`, `test`, `docs`, `ci`, `perf`.
Scopes match the feature area: `groups`, `members`, `expenses`, `settlements`, `activity`, `sync`, `auth`, `invites`, `firebase`, `telemetry`, `env`, `l10n`, `db`, `ui`, `ci`, `store`, `play`, `security`, `e2e`, `deps`, `skills`, `release`, `ios`, `android`, `github`; for docs, the doc area (`product`, `roadmap`, `store`, or the release, e.g. `r3`, `r4`). Check `git log --oneline -30` when unsure.

Example: `feat(expenses): add paid-by dropdown to expense form`

## 5. Write the body

Use this template. Delete sections that don't apply — never leave placeholder text.

```markdown
## Summary
<1–3 sentences: what changes and why, from the user's point of view.>

## Changes
- **Domain:** <entities / use cases / repository interfaces>
- **Data:** <Drift tables, DAOs, mappers, migrations, sync / Firestore — call out schema version bumps and rules changes>
- **Presentation:** <screens, widgets, providers, routes>
- **Other:** <l10n, CI, build config, version bump>

## Screenshots
<Before/after for UI changes. Ask the user for them; leave a "TODO: add screenshots" only if they say so.>

## Testing
- [x] `flutter analyze --fatal-infos`
- [x] `dart format --set-exit-if-changed .`
- [x] `flutter test` — <N tests, note new ones>
- [ ] Manual: <steps actually verified on device/simulator, or what reviewers should verify>

## Notes for reviewers
<What merging does (see below), risky areas, DB migrations, follow-ups, rule violations from step 2.>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Tick a checkbox only for checks that actually ran and passed. List every CI job from step 3 that ran (rules, telemetry, store metadata), not only the Dart three.

Merging is a deploy, so say in Notes for reviewers what this PR's merge sets off (read the workflows' `on:` paths; `../software-engineer/references/ci.md` summarises them):

- App code (`lib/`, `web/`, `assets/`, `pubspec.*`) → the web app, rules and indexes deploy to dev (`simsplit-as-se1-dev.web.app`); `lib/`, `android/`, `assets/` or `pubspec.lock` also upload an Android build to SimSplit [Dev] internal testing.
- `firebase/` → rules and indexes deploy to dev.
- `android/fastlane/metadata/` → `play_metadata.yml` syncs the store listing (and `data_safety.csv`) to **both** Play apps; it goes live on Play after Play's review — production users see it before the next build ships.
- `docs/` → GitHub Pages (landing page, privacy policy) goes live.
- Nothing reaches prd builds or `simsplit.web.app` until a `vYYYY.M.D` tag (`release-manager`).

## 6. Confirm, push, create

Show the user the title and body and wait for approval — opening a PR is outward-facing. Then:

The repo lives under the `mazino2d` GitHub account; if `gh` has several
accounts logged in, prefix `gh` calls with `GH_TOKEN=$(gh auth token --user mazino2d)`.
PRs are squash-merged, so the PR title becomes the commit on `main`.

```bash
git push -u origin HEAD
gh pr create --base <base> --title "<title>" --body-file <scratchpad>/pr_body.md [--draft]
```

Write the body to a file in the scratchpad (not the repo) to avoid shell-quoting issues. Return the PR URL.
