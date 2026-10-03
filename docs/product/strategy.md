# Product strategy

> Source of truth for product decisions. The `product-owner` skill reads this file before
> triaging, writing specs or reordering the roadmap. Change it deliberately — every change
> here shifts what gets built.

Last reviewed: 2026-10-03

## Vision

The calmest way for a group of friends on a trip to know who owes whom — everyone sees
the same numbers, no arguments.

## Primary persona — the trip bookkeeper

- Vietnamese friend group of 3–8 people on a trip or a night out; amounts in VND.
- **One person usually holds the phone** and logs for most expenses. Other members may
  install the app, join the shared group, see balances and add their own expenses
  (co-members), but the default path is still built around the bookkeeper.
- Usage is **episodic**: intense for 2–7 days, then the group is settled and goes quiet.
  A dormant group after settle-up is success, not churn.
- Often on poor mobile data (mountains, islands, abroad) — after the first sign-in the
  app must keep working offline and sync when the signal returns.

Secondary users (served only when it costs the primary persona nothing): housemates,
couples, international travellers.

## Objective (6–12 months)

**Craft / portfolio.** A small, polished, trustworthy app that showcases product and
engineering quality. The app is **product-first**: effort goes into making the UI/UX
excellent, not into monetisation. Growth and revenue are explicitly **not** objectives
(see [principles](principles.md#guiding-stance--product-over-profit)).

## North Star — quality, not adoption

The app ships no telemetry, so the North Star is a set of quality bars measurable by
dogfooding, tests and Play Console:

| Metric | Target | How it is measured |
| --- | --- | --- |
| Time to log an equal-split expense | ≤ 10 s, ≤ 4 taps from the group screen | Manual timed run on a mid-range Android phone, recorded in the PR or spec |
| Crash-free users | ≥ 99.5 % | Play Console → Android vitals |
| Store rating | ≥ 4.5 | Play Console (once production ratings exist) |

A feature that does not move one of these — or a core use case's success criteria — needs
an explicit reason to exist.

## Non-negotiable

- **One shared truth per group.** Every member of a shared group sees the same expenses,
  balances and settlements, and no recorded data is ever lost or silently altered by sync.
- **Full trust, always auditable.** Every member can do everything in a group — no roles,
  no approvals. In return, every change (create, edit, delete) is recorded with who, when
  and what changed, and any member can review that history. The history cannot be edited
  or deleted.
- **Free to run at small scale.** The backend must cost nothing for up to ~100 active
  users; any design that needs a paid plan at that scale is rejected.

*Changed 2026-10-03:* the former "Fully offline core" non-negotiable was narrowed to enable
online shared groups ([R-3](specs/R-3-online-shared-groups.md)). The app requires sign-in
and a network for first use; after that, offline use is a strong default (below).

## Strong defaults (can be challenged, with a written reason)

- Sign-in is a single tap (Google or Apple) — no passwords, no profile setup.
- Offline after sign-in: creating groups, logging expenses, viewing balances and recording
  settlements work with no network and sync later.
- No ads and no third-party analytics SDK.
- Data is stored only to sync groups between their members — never sold, profiled or
  used for anything else; deleting the account deletes the user's cloud data.

These replaced "No account or sign-up" and "Data stays on the device" on 2026-10-03
(see R-3).

These are not red lines, but anything that weakens them must go through triage with the
trade-off written down in the roadmap entry.

## Non-goals (for now)

- Budgeting, personal finance tracking, or bank integration.
- Monetisation (Pro tier, subscriptions, ads).
- Recurring expenses and long-running household features — these serve the secondary
  persona and pull scope away from trips.

## Baseline guardrail — trust in numbers

Not a UX principle to weigh, but a precondition for shipping: every change that touches
money must keep totals exact to the smallest unit (integer cents, see `CLAUDE.md`), assign
rounding remainders deterministically, and never lose or silently alter recorded data.
Specs touching money must include acceptance criteria for this.
