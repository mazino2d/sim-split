# Roadmap and backlog

Maintained by the `product-owner` skill. Ordered by RICE-lite score within each horizon.

**RICE-lite score = Impact × Confidence ÷ Effort**

| Factor | Scale |
| --- | --- |
| Impact — effect on a North Star bar or a core use case criterion | 3 massive · 2 high · 1 medium · 0.5 low · 0.25 minimal |
| Confidence — how sure we are about impact and effort | 1.0 high · 0.8 medium · 0.5 low |
| Effort — focused person-days | number, ≥ 0.5 |

Reach is omitted: there is one persona and no usage data, so it would be the same guess
for every item.

Items are product phases, numbered in order: R-1 built the offline app, R-2 polishes it,
R-3 makes groups co-worked online. Each phase has a spec in [specs/](specs/) that also
records its story. (Renumbered 2026-10-03; earlier backlog items are folded into
[R-2](specs/R-2-ux-polish-and-strategy.md).)

## Shipped

| ID | Item | Serves | Notes |
| --- | --- | --- | --- |
| R-1 | v1.0 offline app: groups, members, expenses with 4 split types, balances with simplified debts, settlements, EN + VI, light/dark | UC-1 – UC-4, UC-6 | Built under the original offline, no-account strategy. Closed test on Google Play submitted 2026-10-03; the offline build (with R-2) reached production as 1.0.0, superseded by 2026.10.22. Story: [R-1](specs/R-1-offline-app.md). Implementation: [R-1](../implementations/R-1-offline-app.md). |
| R-2 | UI/UX polish and strategy clarity: redesign, faster expense and group flows, product docs, timed audit of UC-1 | UC-1.1, all UCs | Redesign shipped in #16; product docs (strategy, principles, use cases, roadmap) written. Timed UC-1 audit passed on 2026-10-07 on a mid-range Android phone: median 5 s (worst 7 s), 2–3 taps. Story: [R-2](specs/R-2-ux-polish-and-strategy.md). Implementation: [R-2](../implementations/R-2-ux-polish-and-strategy.md). |

## Now

| ID | Item | Serves | I | C | E | Score | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R-4 | Error reports and usage analytics: anonymous error reports (on by default, off switch in Settings → Diagnostics) and usage tracking linked to the account, required to use the app, sent through the app's own endpoint to Cloud Logging (alerts) and the maintainer's BigQuery warehouse, kept indefinitely; group data copied to the warehouse; agreed to by signing in, through the privacy policy; every action in the app tracked; a private Evidence dashboard on the dbt models; zero cost by hard limits | UC-6, UC-7, all UCs | 2 | 0.8 | 16 | 0.1 | Triaged 2026-10-08 from tester bug reports on web and Android that could not be reproduced; usage analytics added 2026-10-23 so prioritisation and error rates rest on data, then tracking of every action and a dashboard; effort re-estimated from the implementation plan. Strategy change: narrows "ships no telemetry" and "data is stored only to sync groups" (see [strategy](strategy.md)); no third-party SDK. Trade-offs: error reports are opt-out only while they stay anonymous; usage tracking and the group copy identify the user and are a condition of using the app (complete data over choice; people who don't agree can't use it, and consent is not "freely given" in the GDPR sense). Accounts created before R-4 never agreed, so they and their cloud data are deleted when it ships. It ships in 2026.10.24, with the updated privacy policy and Data safety (`data_safety.csv`). The known bugs are tracked as separate issues, not in this item. Spec: [R-4](specs/R-4-error-reports-and-usage-analytics.md). Plan: [implementation](../implementations/R-4-error-reports-and-usage-analytics.md). |
| R-3 | Co-worked groups: friends log expenses together, see the same split, everyone has full rights, every change is auditable. Google/Apple sign-in, cloud sync, invite link | UC-1, UC-2, UC-4, UC-7, UC-8, UC-9 | 3 | 0.5 | 27 | 0.06 | Strategy change 2026-10-03: drops the no-account default; offline only after first sign-in. Spec: [R-3](specs/R-3-online-shared-groups.md). Backend: Firebase (Blaze at $0, budget + kill switch). Live on [simsplit.web.app](https://simsplit.web.app) and on Android since 2026.10.22. iOS (P8) is on hold: no Apple Developer account for now. Phase status: [implementation](../implementations/R-3-online-shared-groups.md). |

## Next

| ID | Item | Serves | I | C | E | Score | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |

## Later

| ID | Item | Serves | I | C | E | Score | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |

## Rejected / parked

Ideas that were triaged and declined, kept so they are not re-litigated.

| ID | Idea | Decision | Reason | Date |
| --- | --- | --- | --- | --- |
