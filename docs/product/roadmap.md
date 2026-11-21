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
R-3 makes groups co-worked online, R-4 adds error reports and usage analytics, R-5 adds
a dev environment so only tags reach production, R-6 fixes what testers hit after R-3
and R-4, and R-7 settles up. Phases R-1 to R-4 have a spec in [specs/](specs/) that also
records its story; for R-5 to R-7 the issues are the spec. (Renumbered 2026-10-03;
earlier backlog items are folded into [R-2](specs/R-2-ux-polish-and-strategy.md). R-5
and R-6 were named on 2026-11-21, after they shipped, from the work in 2026.11.21.)

## Shipped

| ID | Item | Serves | Notes |
| --- | --- | --- | --- |
| R-1 | v1.0 offline app: groups, members, expenses with 4 split types, balances with simplified debts, settlements, EN + VI, light/dark | UC-1 – UC-4, UC-6 | Built under the original offline, no-account strategy. Closed test on Google Play submitted 2026-10-03; the offline build (with R-2) reached production as 1.0.0, superseded by 2026.10.22. Story: [R-1](specs/R-1-offline-app.md). Implementation: [R-1](../implementations/R-1-offline-app.md). |
| R-2 | UI/UX polish and strategy clarity: redesign, faster expense and group flows, product docs, timed audit of UC-1 | UC-1.1, all UCs | Redesign shipped in #16; product docs (strategy, principles, use cases, roadmap) written. Timed UC-1 audit passed on 2026-10-07 on a mid-range Android phone: median 5 s (worst 7 s), 2–3 taps. Story: [R-2](specs/R-2-ux-polish-and-strategy.md). Implementation: [R-2](../implementations/R-2-ux-polish-and-strategy.md). |
| R-4 | Error reports and usage analytics: anonymous error reports (on by default, off switch in Settings → Diagnostics) and usage tracking linked to the account, required to use the app, sent through the app's own endpoint to Cloud Logging (alerts) and the maintainer's BigQuery warehouse, kept indefinitely; group data copied to the warehouse; agreed to by signing in, through the privacy policy; every action in the app tracked; a private Evidence dashboard on the dbt models; zero cost by hard limits | UC-6, UC-7, all UCs | Triaged 2026-10-08 from tester bug reports on web and Android that could not be reproduced; usage analytics added 2026-10-23 so prioritisation and error rates rest on data, then tracking of every action and a dashboard; effort re-estimated from the implementation plan. Strategy change: narrows "ships no telemetry" and "data is stored only to sync groups" (see [strategy](strategy.md)); no third-party SDK. Trade-offs: error reports are opt-out only while they stay anonymous; usage tracking and the group copy identify the user and are a condition of using the app (complete data over choice; people who don't agree can't use it, and consent is not "freely given" in the GDPR sense). Accounts created before R-4 never agreed, so they and their cloud data are deleted when it ships. It ships in 2026.10.24, with the updated privacy policy and Data safety (`data_safety.csv`). The known bugs are tracked as separate issues, not in this item. Spec: [R-4](specs/R-4-error-reports-and-usage-analytics.md). Plan: [implementation](../implementations/R-4-error-reports-and-usage-analytics.md). Shipped as 2026.10.24 (100 % on 2026-10-24); dashboard at data-platform-dashboard.pages.dev (maintainer only). |
| R-5 | Dev environment and safer releases: a dev Firebase project (`simsplit-as-se1-dev`) and a separate SimSplit [Dev] Play app; every merge to `main` ships to dev, only `v*` tags reach production; production deploys wait for the maintainer's approval in GitHub Environments; the telemetry endpoint ships with releases; dev is smoke-tested after each deploy; dev builds carry a `-dev.<sha>` version | All UCs (release safety) | Engineering phase, no spec. PRs #86, #89–#93, #102, #135 (fixes #126). First production release through it: 2026.11.21 on 2026-11-21. Implementation: [dev environment](../implementations/dev-environment.md). |
| R-6 | Fixes from testers after R-3 and R-4. Sign-in and invites: first sign-in from an invite link (#107), a guide out of in-app browsers such as Zalo (#109), web sign-in on the app's own domain so Safari on iPhone works (#138). Telemetry: stable failure names on web (#108), usage events from short Android sessions sent soon (#128), deleting from a form not counted as abandoning it (#129), symbolized web error reports (#132), copying the app version from Diagnostics (#127). Faster, readable entry: zero shortcuts and amount suggestions for VND (#114), long titles and names wrap (#111), the add-member field stays in view (#113) | UC-1, UC-3, UC-6, UC-7, UC-8 | No spec: the issues are the spec. PRs #131, #133, #134, #136, #137, #139–#144. Shipped as 2026.11.21 on 2026-11-21. |
| R-7 | Settlements: settle through one collector or in the fewest transfers, chosen per group (#116); archive a group when the trip is over, owner only (#117); a "My name" setting prefilled for new groups (#112); each member's share, paid and what's left on one card (#110); the split shared or saved as images for friends without the app (#115) | UC-2, UC-3, UC-4, UC-5 | All phases (P1–P6) and the review follow-ups (#153–#157) shipped as 2026.11.21 on 2026-11-21: web and Firestore rules live, Android sent to Play review at 100 %. No spec document: the issues are the spec. Implementation: [R-7](../implementations/R-7-settlements.md). |

## Now

| ID | Item | Serves | I | C | E | Score | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R-8 | Security hardening after the first security review: infrastructure restricted to what the app needs, Firestore rules that match the app's own limits, a bounded telemetry path, web security headers, pinned CI actions, and security review in the PR and release routine | All UCs (trust, cost) | 1 | 0.8 | 6 | 0.13 | Infrastructure and rules phases done 2026-11-21; telemetry, headers, CI and process next. No spec document. Implementation: [R-8](../implementations/R-8-security-hardening.md). |
| R-3 | Co-worked groups: friends log expenses together, see the same split, everyone has full rights, every change is auditable. Google/Apple sign-in, cloud sync, invite link | UC-1, UC-2, UC-4, UC-7, UC-8, UC-9 | 3 | 0.5 | 27 | 0.06 | Strategy change 2026-10-03: drops the no-account default; offline only after first sign-in. Spec: [R-3](specs/R-3-online-shared-groups.md). Backend: Firebase (Blaze at $0, budget + kill switch). Live on [simsplit.web.app](https://simsplit.web.app) and on Android since 2026.10.22. iOS (P8) is on hold: no Apple Developer account for now. Phase status: [implementation](../implementations/R-3-online-shared-groups.md). Pending since 2026-11-21: everything but iOS (P8) is live; P8 waits for an Apple Developer account. |

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
