# SimSplit — AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Copilot, Cursor, …) and human
contributors working in this repo.

SimSplit is a Flutter app for tracking and splitting group expenses with friends.
Friends sign in with Google, share a group through an invite link and see the same
balances live; every change is kept in an activity history. Data lives in a local Drift
database first and syncs through Firestore, so the app keeps working offline after
sign-in. Product context: [docs/product/strategy.md](docs/product/strategy.md).

## Language policy

**Write everything in English** — code, comments, docs, commit messages, PR
descriptions and identifiers. User-facing strings are localized in the EN and VI ARB
files (`lib/core/l10n/`).

## Critical rules

1. **Clean Architecture is strict:** `lib/domain/` is pure Dart — no Flutter, Drift,
   Firebase, Riverpod or go_router imports. Presentation never imports data.
2. **Money is `int` cents, never `double`.** Splits always sum exactly to the total.
3. **Errors are `Either<Failure, T>`** (fpdart) in domain and data, not exceptions.
4. **Never hand-edit generated files** (`*.g.dart`, `*.freezed.dart`) — rerun codegen.
5. **Never commit secrets:** `android/key.properties`, `*.jks`, `AuthKey_*.p8`.
6. **`group.members` is always empty** — read members with `memberListProvider(groupId)`.
7. **Every Firestore rules change needs a test** in `firebase/test/`.
8. **Every interactive callback is tracked** (R-4): wrap it in `context.tracked(…)` with a
   `TelemetryEvent`, and run use cases through `trackOp` / a notifier's `_run(event, …)`.
   `test/unit/presentation/tracking_coverage_test.dart` fails on an untracked callback.

## Commands

```bash
bash scripts/setup.sh                                      # bootstrap once after installing Flutter
dart run build_runner build --delete-conflicting-outputs   # after changing models / DAOs / providers
flutter gen-l10n                                           # after changing ARB files
flutter analyze --fatal-infos                              # ┐
dart format --output=none --set-exit-if-changed .          # ├ CI on Dart changes (see below)
flutter test                                               # ┘
cp .env.example .env.local                                 # once: local build settings (gitignored)
flutter run -d chrome --dart-define-from-file=.env.local   # run the app (on Android add --flavor prd|dev)
```

Commits and PR titles use Conventional Commits (`feat(expenses): …`).

### What CI runs on every PR

`.github/workflows/pr_validate.yml` runs only the jobs whose paths changed (a skipped job
counts as passing) and reports one required check, `PR Validation`. This is the complete
list; skills and other docs point here instead of copying it.

| Job | Runs when the diff touches | Run it locally |
| --- | --- | --- |
| Format, Analyze, Test | `lib/`, `test/`, `pubspec.*`, `analysis_options.yaml`, `build.yaml`, `l10n.yaml`, `.github/actions/flutter-setup/` | `flutter pub get`, codegen and `gen-l10n`, then the three commands above |
| Store metadata | `android/fastlane/metadata/`, `android/fastlane/whatsnew/`, `scripts/play_metadata.py` | `python3 scripts/play_metadata.py check` |
| Firestore rules | `firebase.json`, `firebase/` | `npm ci --prefix firebase/test`, then `npx firebase-tools@14 emulators:exec --only firestore --project demo-simsplit "npm --prefix firebase/test test"` (needs Java) |
| Telemetry endpoint | `services/telemetry/` | `npm ci --prefix services/telemetry`, then `npm --prefix services/telemetry run typecheck` and `npm --prefix services/telemetry test` |
| Lint workflows | `.github/workflows/`, `.github/actions/` | actionlint (the shared `lint.yml` in mazino2d/github-workflows) |

A change to `pr_validate.yml` itself runs every job.

### Environments

Two environments, picked with `--dart-define=APP_ENV=dev|prd` (default `prd`) and, on
Android, the matching `--flavor dev|prd`: **dev** (`simsplit-as-se1-dev`,
`com.mazino2d.simsplit.dev`, `simsplit-as-se1-dev.web.app`) gets every push to `main`; **prd**
(`simsplit-as-se1-prd`, `com.mazino2d.simsplit`, `simsplit.web.app`) gets only tags
(`vYYYY.M.D-rc.N` → Play alpha, `vYYYY.M.D` → Play production, web, Firestore rules and
indexes). CI jobs that deploy run in the GitHub Environment of the same name (plus
`store` for Play listing and rollout); every `prd` job waits for the maintainer's
approval. Anything that differs per environment reads `appEnv`
(`lib/core/constants/app_env.dart`); never hardcode a project, package or domain.

## Destructive and production actions

These cannot be undone or reach real users. Never run them on your own initiative, even
when a skill or a script's docstring shows the command: list what would be affected
(accounts, tags, releases, documents, users) and wait for the user to do it or say yes.

- **Never run `scripts/wipe_accounts.py --yes`.** It deletes every Firebase Auth user and
  all Firestore data in `simsplit-as-se1-prd`, plus the warehouse copy in
  `simsplit_raw` (`dataplatform-as-se1-prd`). Without `--yes` it only counts.
- **Never delete** tags or branches on `origin`, GitHub Releases, Play releases, Firestore
  documents or BigQuery tables and rows.
- **Never approve a `prd` deployment** — not in the run's **Review deployments**, not
  through the `pending_deployments` API. The maintainer approves every `prd` job in the
  run UI.
- Pushing a `v*` tag, running `play_rollout.yml` and merging to `main` (which deploys dev
  and syncs both Play listings) wait for the user's explicit go-ahead.

## Skills

Detailed workflows live in [.claude/skills/](.claude/skills/), one folder per task with a
`SKILL.md` entry point. Claude Code loads them automatically; other agents should read
the matching `SKILL.md` before starting the task.

| Task | Skill |
| --- | --- |
| Write or change code, tests, l10n; write implementation plans | [`software-engineer`](.claude/skills/software-engineer/SKILL.md) — architecture, design system, testing; plans in `docs/implementations/` |
| Keep README, site, privacy policy, store listing and other docs in sync with a change; audit docs for drift | [`docs-writer`](.claude/skills/docs-writer/SKILL.md) — doc map of every fact's source and mirrors |
| Open a pull request | [`pr-writer`](.claude/skills/pr-writer/SKILL.md) |
| Verify a branch or PR before merge (builds + end-to-end use cases) | [`e2e-tester`](.claude/skills/e2e-tester/SKILL.md) |
| Plan, check and ship a release to Google Play (CalVer `YYYY.M.D`, release candidate, tag, Play Console) | [`release-manager`](.claude/skills/release-manager/SKILL.md) — preflight checklist and release flow |
| Triage ideas, write specs, update the roadmap | [`product-owner`](.claude/skills/product-owner/SKILL.md) — strategy and specs in `docs/product/` (public on GitHub Pages) |
| App icon, splash, Play Store and App Store graphics, landing page images | [`uiux-designer`](.claude/skills/uiux-designer/SKILL.md) — SVG masters in `design/`, one pipeline in `design/build.py` |
| A production error or outage: triage, severity, same-day hotfix | [`incident-responder`](.claude/skills/incident-responder/SKILL.md) — R-4 error reports, read-only queries, hand-off to `release-manager` |
| Telemetry endpoint, tracked events, usage questions to the warehouse | [`telemetry-analyst`](.claude/skills/telemetry-analyst/SKILL.md) — `services/telemetry/`, event schema, privacy rules, read-only BigQuery |
