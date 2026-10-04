# R-1 Offline app (v1.0)

Status: shipped   ·   Serves: UC-1, UC-2, UC-3, UC-4, UC-6   ·   Roadmap: Shipped

A record of the first phase: what we set out to build, what we built, and what we
learned. Written after the fact on 2026-10-03 from the commit and PR history.

## The idea

Splitting costs on a trip with friends usually ends up in a chat full of screenshots and
"wait, who paid for the taxi?". The existing apps want everyone to sign up and expect a
good connection, which is often missing in the mountains, on islands or abroad.

R-1 bet on the opposite: **one person holds the phone, logs for everyone, and the app works
with no network and no account.** All data stays on the device.

## Strategy at the time

- **Non-negotiable:** a fully offline core. Creating groups, logging expenses, viewing
  balances and recording settlements must work with no network, forever.
- **Strong defaults:** no account or sign-up, no ads or analytics, data stays on the
  device.
- **Persona:** the trip bookkeeper. The other friends never install the app.
- **Guardrail:** trust in numbers. Money is stored as integer cents, totals are always
  exact, and rounding is deterministic.

## What we built

| Area | Capability |
| --- | --- |
| Groups | Create, edit and delete a group with a name, an emoji and a currency (VND by default). The currency locks once the group has expenses. |
| Members | Add, rename and remove members. One member is marked as "me". A member who appears in any expense or settlement cannot be removed. |
| Expenses | Amount, title, category, date, note, payer, and 4 split types: equal, percentage, exact and shares. Edit and delete. |
| Balances | Net balance per member and suggested transfers, using a greedy rule (largest debtor pays largest creditor, at most N−1 transfers). |
| Settlements | Record a payment between two members, see settlement history, delete a mistaken one. |
| Settings | Language (EN, VI) and theme. |
| Platforms | Android (Google Play), plus web and iOS builds. |

How it was built (architecture, algorithms, PR history):
[R-1 implementation](../../implementations/R-1-offline-app.md).

## Timeline

- **2026-04-07 → 04-11 — first build.** Project setup, groups, members and expenses, EN/VI
  localisation, the payer dropdown, package name `com.mazino2d.simsplit`, a privacy policy,
  and a first draft upload to Play (v1.0.0+5).
- **Pause** of about six months.
- **2026-10-02 → 10-03 — hardening for release** (PRs #2–#15):
  - Domain validation (#3). Negative or duplicate split inputs are rejected. Leftover cents
    are distributed with the largest-remainder method, so a member with weight 0 never
    pays a cent. Expense writes are atomic. An unknown member returns a failure instead of
    crashing.
  - Presentation fixes (#5). Amounts are currency-aware ("12.50" in USD used to be saved
    as $1,250.00). The settlement flow and Back navigation were fixed, and duplicate saves
    were removed.
  - Localised domain errors (#6). Fixed the web group form hanging on Save (#7).
  - Release pipeline. Parallel CI with cached codegen (#8, #14). Play upload through
    Workload Identity Federation (#9). Store icon and screenshots (#10). The Play listing
    is managed from the repo (#11–#13).
  - Settlement history and deleting a settlement (#15).
- **2026-10-03 — closed test on Google Play submitted.**

## Key decisions and why

- **Integer cents everywhere, with deterministic remainders.** Without this, nobody trusts
  the numbers. Equal splits give the first members the extra cent. Percentage and shares
  use largest-remainder allocation.
- **Balances are computed, not stored.** They are always derived from expenses and
  settlements, so deleting a mistaken settlement simply brings the debt back.
- **Members with history cannot be removed.** Removing them would silently change other
  people's balances.
- **Greedy debt simplification, not the true minimum.** It is simple, deterministic, and
  gives at most N−1 transfers, which is good enough for groups of 3–8 people.

## What we learned

- Most of the release work was hardening, not features. The first build had money bugs
  (the ×100 decimal bug, leftover cents that could not be settled) that would have broken
  trust in numbers. The guardrail earned its place.
- The Play listing promised a feature that did not exist (exporting a summary). This led to
  the R-2 rule that the store listing is checked against the app.
- The UI was functional but slow. Logging an expense took more taps than the ≤ 4-tap target
  allowed, which became the focus of R-2.
- The "one person holds the phone" bet left the other friends asking the bookkeeper "how
  much do I owe?". That question became R-3.

## Out of scope (by design at the time)

- Accounts, sync, sharing between devices, and real-time collaboration.
- Multi-currency conversion, recurring expenses and budgeting.
