---
name: dev
description: Implement a change in the SimSplit Flutter codebase — features, fixes, refactors, tests — following its strict Clean Architecture (pure-Dart domain, Drift + Firestore sync data layer, Riverpod presentation), integer-cents money, Either-based errors, the monochrome design system, codegen and EN/VI localization. Use for any coding task in this repo, even a small one: adding or changing a screen, widget, use case, repository, Drift table or migration, sync/Firestore code, provider or l10n string, writing tests, fixing a bug, or writing an implementation plan in docs/implementations/.
---

# SimSplit development

The critical rules and commands are in `AGENTS.md` at the repo root — they apply to
every change. This skill adds the workflow and the per-layer detail.

## References

Read the reference that matches the layer you touch before writing code:

| Touching | Read |
| --- | --- |
| `lib/domain/`, `lib/data/` (incl. `sync/`), `lib/core/di/` | [references/architecture.md](references/architecture.md) |
| `lib/presentation/` (screens, widgets, providers, theme) | [references/presentation.md](references/presentation.md) |
| `.github/workflows/`, `firebase/`, releases, store metadata | [references/ci.md](references/ci.md) |

## Implementation plans

A roadmap item big enough to span several PRs gets a plan in
`docs/implementations/<R-id>-<slug>.md`, using the same slug as its spec in
`docs/product/specs/` (the spec is owned by the `product-owner` skill and says *what*; the plan
says *how*). Header: `Status · Spec link · date`. Then sections for decisions (with
why), architecture, phases (one or two PRs each, mapped to spec ACs, with effort in days),
manual steps and risks. Update the phase table as phases ship. Never change acceptance
criteria here — raise spec changes with the product owner.

## Workflow

1. **Locate.** Find the use case, repository, provider and screen involved.
   Prefer extending an existing use case or widget over adding a parallel one.
2. **Change inward-out.** Domain (entity / use case / repository interface)
   → data (table, DAO, mapper, repository impl) → DI in
   `lib/core/di/injection.dart` → presentation. Skip layers that don't change.
3. **Regenerate** (`build_runner`, `gen-l10n`) after touching any `@freezed`
   model, Drift table/DAO or `@riverpod` provider, and after editing ARB files.
   Generated files are gitignored, so stale ones cause compile errors that
   look unrelated to your change.

4. **Test** at the right level (see Testing below). Bug fixes start with a
   failing test that reproduces the bug.
5. **Check** with exactly what CI runs (analyze, format, test — see
   `AGENTS.md`). If `firebase/` changed, also run the rules tests
   ([references/ci.md](references/ci.md)).

6. **See it.** For UI changes, render the screen (golden preview with
   provider overrides, or `flutter run -d chrome`) and look at it in light
   and dark before calling it done.
7. **Commit** with Conventional Commits (`feat(expenses): …`). Open the PR
   with the `write-pr` skill.

## Testing

- Domain use cases: unit tests with `mocktail` mocks of repository
  interfaces (`test/helpers/mocks.dart` has shared mocks and fixtures).
- Data repositories: an in-memory Drift database — never mock the DB.
- Widgets: `ProviderScope` overrides for providers and use cases; wrap in
  `MaterialApp.router` with a `GoRouter` when the screen navigates.
- Sync: drive the recorder, pusher and puller against an in-memory Drift
  database and `fake_cloud_firestore`; check that a change and its activity
  entry always travel together.
- Critical suites: `calculate_splits_test.dart`, `calculate_debts_test.dart`.
- A new screen or user flow also gets a step in `integration_test/` (the
  `e2e-tester` skill runs it).
- Test names are descriptive English sentences.

## File naming

| Type | Convention | Example |
| --- | --- | --- |
| Use cases | `verb_noun.dart` | `create_group.dart` |
| Screens | `noun_screen.dart` | `group_list_screen.dart` |
| Notifiers | `noun_notifier.dart` | `group_notifier.dart` |
| Drift repositories | `drift_noun_repository.dart` | `drift_group_repository.dart` |
| Mappers | `noun_mapper.dart` | `group_mapper.dart` |
