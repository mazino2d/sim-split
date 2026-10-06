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

## Commands

```bash
bash scripts/setup.sh                                      # bootstrap once after installing Flutter
dart run build_runner build --delete-conflicting-outputs   # after changing models / DAOs / providers
flutter gen-l10n                                           # after changing ARB files
flutter analyze --fatal-infos                              # ┐
dart format --output=none --set-exit-if-changed .          # ├ what CI runs on every PR
flutter test                                               # ┘
flutter run -d chrome                                      # run the app on web
```

Commits and PR titles use Conventional Commits (`feat(expenses): …`).

## Skills

Detailed workflows live in [.claude/skills/](.claude/skills/), one folder per task with a
`SKILL.md` entry point. Claude Code loads them automatically; other agents should read
the matching `SKILL.md` before starting the task.

| Task | Skill |
| --- | --- |
| Write or change code, tests, l10n; write implementation plans | [`software-engineer`](.claude/skills/software-engineer/SKILL.md) — architecture, design system, testing; plans in `docs/implementations/` |
| Open a pull request | [`pr-writer`](.claude/skills/pr-writer/SKILL.md) |
| Verify a branch or PR before merge (builds + end-to-end use cases) | [`e2e-tester`](.claude/skills/e2e-tester/SKILL.md) |
| Triage ideas, write specs, update the roadmap | [`product-owner`](.claude/skills/product-owner/SKILL.md) — strategy and specs in `docs/product/` (public on GitHub Pages) |
| App icon, splash, Play Store graphics | [`uiux-designer`](.claude/skills/uiux-designer/SKILL.md) — SVG masters in `design/` |
