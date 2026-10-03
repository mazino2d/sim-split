# R-2 UX polish and strategy clarity

Status: in progress   ·   Serves: UC-1.1, all UCs   ·   Roadmap: Now

A record of the second phase: making the working v1.0 app feel fast and calm, and writing
down the product strategy so later decisions are deliberate. Written on 2026-10-03.

## Why this phase

R-1 worked, but it did not feel good to use. Logging an expense — the core loop — took too
many taps. Balances and settlements were spread across tabs, and the look was a default
Material app. The product decisions also lived only in one person's head, so every new
idea was argued from scratch.

The stance for R-2: **product over profit.** The goal is the best UI/UX for the core use
cases, not revenue. Polish counts as real work.

## What we did

### 1. Wrote the strategy down (`docs/product/`)

- [strategy.md](../strategy.md): vision, the trip-bookkeeper persona, a craft/portfolio
  objective, North Star quality bars (≤ 10 s and ≤ 4 taps to log an expense, ≥ 99.5 %
  crash-free users, ≥ 4.5 rating), the non-negotiable, strong defaults and non-goals.
- [principles.md](../principles.md): Calm and frictionless first, then Fast capture. Calm
  wins when they conflict.
- [use-cases.md](../use-cases.md): core and supporting use cases with measurable success
  criteria.
- [roadmap.md](../roadmap.md): a RICE-lite backlog, maintained by the `product-owner`
  skill.

### 2. Redesigned the app (PR #16)

- **Logging an expense is now amount → Save.** The amount comes first, gets focus
  automatically and has live thousands grouping. The description is optional and falls
  back to the category. The payer defaults to whoever paid last. Equal splits can leave
  people out. Uneven splits sit behind a switch.
- **Creating a group** is a continuous "type a name, Enter" flow. Your own name is
  remembered for the next group.
- **One Settle up tab** combines who pays whom, per-member balance bars and history.
- **Home** shows a "You're owed / You owe" summary per currency.
- **Swipe right** on an expense to edit its description, **swipe left** to delete it.
- A **monochrome brand** with Be Vietnam Pro (bundled, so the app stays offline) and a new
  icon: a split coin, half solid (paid) and half outlined (owed).

### 3. Made the outside match the inside

- One image pipeline produces the app icons, Play and App Store graphics, and the landing
  page in EN and VI (#17).
- The Play listing is planned on every PR and applied on merge (#18).
- The listing promised "Export expense summaries to share with the group", which the app
  could not do. The claim was removed (#19), and the old backlog item for it was dropped.
  UC-5 stays as an unbuilt use case.

### 4. Safety net for change

- A security policy, Dependabot, CodeQL and a read-only `GITHUB_TOKEN` (#21, #27).
- Flutter 3.47 and dependency upgrades (#22–#26, #28).
- An end-to-end suite that drives the real app in Chrome, one test per use case, plus the
  `e2e-tester` skill that gives a go/no-go verdict before merging (#29).

## What is left

- **Timed audit of UC-1** on a mid-range Android phone against the ≤ 10 s / ≤ 4-tap bar.
  This was originally its own backlog item and is now part of R-2. Its result feeds new
  polish items.
- **Manual Android checks** of the redesign: haptics, predictive back and keyboard
  behaviour.

## What we learned

- Writing the strategy down made trade-offs visible. For example, Calm beats Fast capture,
  so hints must be inline and dismiss themselves.
- With strategy written down, the next big question could be asked properly: the
  bookkeeper still has to read balances out to friends. Answering it meant deliberately
  changing the strategy (dropping "no account" and narrowing "offline") rather than
  drifting into it. That decision is R-3.

## Hand-off to R-3

- The strategy was revised on 2026-10-03 for co-worked groups. See
  [R-3](R-3-online-shared-groups.md).
- Polish rules from R-2 still apply in a shared group. The ≤ 4-tap expense flow must not
  get slower (R-3 AC20).
