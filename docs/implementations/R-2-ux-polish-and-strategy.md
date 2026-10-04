# R-2 UX polish and strategy clarity — implementation

Status: in progress   ·   Spec: [R-2 UX polish and strategy clarity](../product/specs/R-2-ux-polish-and-strategy.md)   ·   Backfilled 2026-10-04 from commit and PR history

How the R-2 redesign, the asset pipeline and the delivery safety net were built.

## Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Scope of the redesign | Presentation only. No domain or data changes and no schema bump (#16) | The UX improved without touching tested money logic. |
| Theme | `AppTheme` with monochrome light and dark tokens, a `MoneyColors` extension for owed/owe, tabular figures | One source for colours. Screens never hard-code colours. |
| Font | Be Vietnam Pro, bundled under the OFL | Correct Vietnamese diacritics, and the app stays offline (no runtime font fetch). |
| Shared widgets | `MemberAvatar`, `MoneyText`, `EmptyState`, `SectionLabel`, `ExpenseCategoryUi` | One consistent look. Every new screen reuses them. |
| Brand assets | Hand-written SVG masters in `design/`; one pipeline (`design/build.py`) renders icons, splash, Play and App Store graphics, and the landing page (#17) | Reproducible images; no hand-exported PNGs. |
| Store screenshots | Generated from the app (`design/store/capture_test.dart`) and framed by script | Screenshots stay in sync with the UI. |
| Store listing | Plan on PR (`pull_request_target`, dry run, sticky comment), apply on merge (#18) | Same GitOps flow as infrastructure. PR code never runs with the Play token. |
| Product docs | `docs/product/` on GitHub Pages; maintained by the `product-owner` skill | Decisions are written down and public. |
| Engineering rules | `CLAUDE.md` reduced to an index; detailed rules moved into the `software-engineer:dev` skill | Rules load only when they are relevant. |

## What changed in the app (#16)

- **Expense form:**
  - The amount comes first, is focused automatically, and has live thousands grouping.
  - The description is optional and falls back to the category name.
  - Category chips.
  - One-tap payer and participant pickers. The payer defaults to the last payer in the
    group.
  - Equal splits can leave people out. Uneven splits sit behind a switch.
  - A full-width Save button above the keyboard.
- **Group form:**
  - An always-visible "Add a person" field: Enter adds the name and keeps focus. A pending
    name is still added on Create.
  - Your own name is remembered in `shared_preferences`.
  - Emoji and currency chips.
- **Group detail:**
  - A header with total spent, your share and your balance.
  - Balances, transfers and history merged into one Settle up tab.
  - Day totals in the expense list.
  - Swipe right to edit (description focused), swipe left to delete.
- **Home:** a "You're owed / You owe" summary per currency, and an actionable empty state.
- **Settings:** theme setting (Light / Dark / System).
- **Platform:** predictive-back transitions and haptics.

## Safety net

| PR | Change |
| --- | --- |
| #19 | Removed a store-listing claim the app could not meet (export summary) |
| #21 | `SECURITY.md`, Dependabot (pub + Actions), CodeQL for workflows |
| #22–#26, #28 | Flutter 3.47, dependency bumps, lockfile SDK floor, analyzer excludes for platform folders |
| #27 | Every workflow defaults `GITHUB_TOKEN` to read-only |
| #29 | `integration_test/app_test.dart` drives the real app in Chrome (real Drift web worker, router and providers). There is one journey per use case, and data must survive a relaunch. The `e2e-tester` skill gives a go/no-go verdict per use case. |

## Testing

- The suite grew to 119 unit and widget tests. New form tests cover thousands grouping,
  partial-participant splits, the last-payer default, rejecting an empty split, continuous
  member entry, and the remembered name.
- The e2e suite runs before merge through the `e2e-tester` skill. It is not yet a CI job.

## Remaining

- **Timed UC-1 audit:** on a mid-range Android phone, measure against the ≤ 10 s and
  ≤ 4-tap bar. Record the result in the R-2 spec.
- **Manual Android check of the redesign:** haptics, predictive back and keyboard
  behaviour.
