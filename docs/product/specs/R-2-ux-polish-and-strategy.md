# R-2 UX polish and strategy clarity

Status: shipped   ·   Serves: UC-1.1, all UCs   ·   Roadmap: Shipped

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

An end-to-end suite now checks every use case before merge (#29), alongside security and
dependency upkeep. Details: [R-2 implementation](../../implementations/R-2-ux-polish-and-strategy.md).

## UC-1 audit

Run on 2026-10-07 on a mid-range Android phone with the closed-test build, in a group of
four. Each run went from the open group screen to the new expense showing in the list,
with a 6-digit amount and a short description.

| Bar | Target | Result |
| --- | --- | --- |
| Time | ≤ 10 s | 5, 6, 5, 7, 5 s: median 5 s, worst 7 s |
| Taps | ≤ 4 | 2 for amount → Save, 3 with a description (Add expense, description field, Save) |

Payer, split, currency and date need no taps in the common case: the payer defaults to
the last payer, the split to everyone and the date to today. The widget test for the
last-payer default and the UC-1 e2e journey keep the 2-tap path covered.

The manual Android checks of the redesign also passed: a haptic on Save, predictive back
asks before discarding a filled form, and the keyboard never covers Save.

Possible follow-up polish: let the keyboard's Done key save, so the thumb does not have to
reach for Save.

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
