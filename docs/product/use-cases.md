# Use cases and success criteria

Core use cases carry measurable success criteria; a change that regresses one is a bug.
Supporting use cases must work correctly but are optimised only when it costs the core
nothing.

## Core

### UC-1 Log an expense

> As the trip bookkeeper, I record what someone just paid so I can stop thinking about it.

| # | Success criterion |
| --- | --- |
| 1.1 | Equal split among all members: ≤ 10 s and ≤ 4 taps from the group screen to saved. |
| 1.2 | Works with no network, including right after a cold start. |
| 1.3 | Defaults (payer, split, currency, date) are correct without touching them in the common case. |
| 1.4 | Saved amounts and per-member shares always sum exactly to the total. |
| 1.5 | A mistaken entry can be edited or deleted in ≤ 3 taps from the expense list. |

### UC-2 See who owes whom

> As anyone in the group, I want to know what I owe or am owed, and why.

| # | Success criterion |
| --- | --- |
| 2.1 | Balances are reachable in 1 tap from the group screen. |
| 2.2 | Debts are simplified to the minimum practical number of transfers. |
| 2.3 | Every balance can be explained: the user can see which expenses produced it. |
| 2.4 | Balances update immediately after any expense or settlement change. |
| 2.5 | Amounts are formatted in the group currency and the user's locale. |

## Supporting

| ID | Use case | Bar |
| --- | --- | --- |
| UC-3 | Set up a group and its members | Works offline; no contacts permission; members can be added mid-trip. |
| UC-4 | Record a settlement | Settled debts disappear from balances; history is visible. |
| UC-5 | Share the result with the group | Plain-text or image summary to any messaging app. *(Not built.)* |
| UC-6 | Manage settings (language, theme) | Changes apply without restart. |
