# Doc map

Every fact that appears in more than one place has **one source of truth** and a
list of **mirrors**. When the source changes, every mirror changes in the same PR.
When a mirror disagrees with the source, the source wins — unless the source is
itself out of date, in which case fix the source first and say so.

Sources marked *(code)* are not docs: read the code or config, never another doc.

## Product facts

| Fact | Source of truth | Mirrors |
| --- | --- | --- |
| What the app does (features) | *(code)* `lib/`, then `docs/product/use-cases.md` | `README.md` § Features · `docs/index.html` (hero, feature cards, meta descriptions) · `android/fastlane/metadata/android/{en-US,vi}/{short,full}_description.txt` |
| Platform availability (web live, Android track, iOS) | `docs/product/roadmap.md` and the current plan in `docs/implementations/` | `README.md` intro · `docs/index.html` status line · `docs/product/index.md` phase table · store descriptions |
| Phase status (shipped / in progress / held) | the plan's phase table in `docs/implementations/<R-id>-*.md` | `docs/product/roadmap.md` · `docs/product/index.md` · the spec's story section in `docs/product/specs/` |
| Acceptance criteria | `docs/product/specs/<R-id>-*.md` (owned by `product-owner`) | plan phases (reference ACs by ID, never restate them) · `firebase/firestore.rules` comments and `firebase/test/` names |
| Vision, persona, non-goals | `docs/product/strategy.md` (owned by `product-owner`) | `docs/product/principles.md` · `CONTRIBUTING.md` (links only) · issue forms (links only) |

## Privacy and security

| Fact | Source of truth | Mirrors |
| --- | --- | --- |
| What data is collected, where it lives, who sees it | *(code)* `lib/data/`, `firebase/firestore.rules`, `firebase.json` | `docs/privacy-policy.html` · `README.md` § Privacy · `docs/index.html` privacy section · `SECURITY.md` scope · Play Data safety (`android/fastlane/metadata/android/data_safety.csv`, uploaded by `play_metadata.yml`) |
| How to report a vulnerability | `SECURITY.md` | `CODE_OF_CONDUCT.md` § Enforcement · `CONTRIBUTING.md` · `.github/ISSUE_TEMPLATE/config.yml` |
| License | `LICENSE` | `README.md` § License · `CONTRIBUTING.md` § License |

## Engineering facts

| Fact | Source of truth | Mirrors |
| --- | --- | --- |
| Critical rules (Clean Architecture, cents, Either, codegen, secrets, members, rules tests) | `AGENTS.md` § Critical rules | `README.md` § Key rules · `CONTRIBUTING.md` § Rules of the codebase · `.claude/skills/pr-writer/SKILL.md` review checklist · `.github/pull_request_template.md` checklist |
| Developer commands (setup, codegen, l10n, CI checks, run) | `AGENTS.md` § Commands, checked against `scripts/` and `.github/workflows/pr_validate.yml` | `README.md` § Getting Started / Common commands · `CONTRIBUTING.md` § Set up / Before you open a pull request · `.claude/skills/software-engineer/SKILL.md` · `.claude/skills/pr-writer/SKILL.md` step 3 |
| Flutter version, toolchain | *(code)* `.github/actions/flutter-setup/action.yml`, `pubspec.yaml` | `README.md` § Tech Stack / Requirements · `CONTRIBUTING.md` § Set up · `.devcontainer/Dockerfile` (`FLUTTER_VERSION`) |
| Workflow triggers and results | *(code)* `.github/workflows/*.yml` | `README.md` § CI/CD · `.claude/skills/software-engineer/references/ci.md` |
| Release process, versionCode, tracks | *(code)* `.github/workflows/release.yml`, `release_candidate.yml`, `play_rollout.yml`, `build_android.yml` | `README.md` § Releasing / versionCode · `.claude/skills/software-engineer/references/ci.md` · `.claude/skills/release-manager/SKILL.md` § Version scheme / How a release flows |
| Required secrets, WIF identities | *(code)* workflows + `mazino2d/everything-as-code` | `README.md` § Required GitHub Secrets · `android/fastlane/README.md` |
| Environments (dev and prd: Firebase projects, Android packages and flavors, web domains, `APP_ENV`, what ships where) | *(code)* `lib/core/constants/app_env.dart`, `.github/workflows/build_android.yml`, `firebase_deploy.yml`, `release.yml`, `.firebaserc` | `AGENTS.md` § Environments · `README.md` § Environments · `.claude/skills/software-engineer/references/ci.md` · `.claude/skills/release-manager/SKILL.md` § Version scheme · `docs/implementations/dev-environment.md` (decisions) · `.claude/skills/pr-writer/SKILL.md` § Write the body (what merging does) |
| CI jobs on every PR (jobs, path filters, local commands) | *(code)* `.github/workflows/pr_validate.yml` | `AGENTS.md` § What CI runs on every PR (the one full list) · `README.md` § CI/CD · `.claude/skills/software-engineer/references/ci.md` · `.claude/skills/pr-writer/SKILL.md` and `.claude/skills/e2e-tester/SKILL.md` (link to `AGENTS.md`, never copy) |
| Destructive and production actions (what agents never do alone) | `AGENTS.md` § Destructive and production actions | `.claude/skills/release-manager/SKILL.md` § Ship · `.claude/skills/incident-responder/SKILL.md` · `.claude/skills/telemetry-analyst/SKILL.md` · `.claude/skills/e2e-tester/SKILL.md` (emulator only) |
| Telemetry event schema, scrubbing, warehouse tables | *(code)* `services/telemetry/src/schema.ts`, `scrub.ts`, `lib/domain/entities/telemetry/telemetry_event.dart`, `lib/data/telemetry/scrubber.dart` | `docs/implementations/R-4-error-reports-and-usage-analytics.md` § Architecture · `.claude/skills/telemetry-analyst/SKILL.md` · privacy row above |
| Local build settings (`--dart-define`s) | `.env.example` | `.claude/skills/software-engineer/SKILL.md` § Local build settings · `AGENTS.md` § Commands |
| Store text limits, metadata pipeline | *(code)* `scripts/play_metadata.py` | `android/fastlane/README.md` |
| Conventional Commit types and scopes | `.claude/skills/pr-writer/SKILL.md` | `CONTRIBUTING.md` § Pull requests · `AGENTS.md` |
| PR body sections | `.claude/skills/pr-writer/SKILL.md` § Write the body | `.github/pull_request_template.md` |
| Skill list | `.claude/skills/*/SKILL.md` front matter | `AGENTS.md` § Skills table |
| Design tokens | *(code)* `lib/presentation/theme/app_theme.dart` | `docs/index.html` `:root` tokens · `.claude/skills/uiux-designer/references/specs.md` |

## Changed path → docs to check

Use this to go from a diff to the rows above.

| Diff touches | Check |
| --- | --- |
| `lib/presentation/` new screen or flow, `lib/domain/use_cases/` | Features row; use-cases; store text if the change is visible on Play |
| `lib/data/`, `lib/data/sync/`, `firebase/firestore.rules`, auth | Privacy row; `SECURITY.md` scope |
| `lib/core/l10n/*.arb` | Nothing in docs, unless a feature name changed — then the Features row |
| `.github/workflows/`, `.github/actions/` | Workflow, release, secrets and Flutter version rows |
| `.devcontainer/` | Flutter version row · `CONTRIBUTING.md` § Codespaces |
| `scripts/`, `pubspec.yaml`, `.env.example` | Commands, toolchain and local build settings rows |
| `.claude/skills/` | Skill list row; any rule or template the skill owns |
| `docs/implementations/` phase table | Phase status and availability rows |
| `docs/product/` | Owned by `product-owner` — only fix links, typos and mirrors that point at it |
| `android/fastlane/metadata/` | EN and VI changed together; limits pass `python3 scripts/play_metadata.py check` |

## Known pitfalls

- `docs/` is published on GitHub Pages. Nothing private (tester names, emails,
  internal URLs, secrets) goes there.
- The store listing ships on merge to `main` (`play_metadata`), and `docs/` goes live
  on merge too. Treat both as user-facing releases.
- Android 1.0 is offline-only and collects nothing; the web app and Android 2026.10.22
  and later (CalVer) sign in and sync. Privacy text must keep both true until 1.0 is gone.
- Specs and strategy belong to the `product-owner` skill. Don't change acceptance
  criteria, non-goals or the North Star from here — raise it instead.
