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
| R-1 | v1.0 offline app: groups, members, expenses with 4 split types, balances with simplified debts, settlements, EN + VI, light/dark | UC-1 – UC-4, UC-6 | Built under the original offline, no-account strategy. Closed test on Google Play submitted 2026-10-03. Story: [R-1](specs/R-1-offline-app.md). Implementation: [R-1](../implementations/R-1-offline-app.md). |
| R-2 | UI/UX polish and strategy clarity: redesign, faster expense and group flows, product docs, timed audit of UC-1 | UC-1.1, all UCs | Redesign shipped in #16; product docs (strategy, principles, use cases, roadmap) written. Timed UC-1 audit passed on 2026-10-07 on a mid-range Android phone: median 5 s (worst 7 s), 2–3 taps. Story: [R-2](specs/R-2-ux-polish-and-strategy.md). Implementation: [R-2](../implementations/R-2-ux-polish-and-strategy.md). |

## Now

| ID | Item | Serves | I | C | E | Score | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R-4 | Anonymous error reports: the app records errors and the screens and actions leading to them, sends them to the app's own Firestore with no account, names or amounts, keeps them 30 days; on by default, off switch in Settings | UC-7, all UCs | 2 | 0.8 | 4 | 0.4 | Triaged 2026-10-08 from tester bug reports on web and Android that could not be reproduced. Strategy change: narrows "ships no telemetry" (see [strategy](strategy.md)); no third-party SDK (Crashlytics was ruled out: no web support). Ship before v2.0.0 so the privacy policy and Data safety change once. Trade-off: opt-out instead of opt-in is acceptable only while reports stay anonymous; linking reports to accounts would need opt-in. The known bugs are tracked as separate issues, not in this item. Spec: [R-4](specs/R-4-anonymous-error-reports.md). |
| R-3 | Co-worked groups: friends log expenses together, see the same split, everyone has full rights, every change is auditable. Google/Apple sign-in, cloud sync, invite link | UC-1, UC-2, UC-4, UC-7, UC-8, UC-9 | 3 | 0.5 | 27 | 0.06 | Strategy change 2026-10-03: drops the no-account default; offline only after first sign-in. Spec: [R-3](specs/R-3-online-shared-groups.md). Backend: Firebase (Blaze at $0, budget + kill switch). Android, web and iOS; 2026-10-05: web reaches parity with Android right after push (plan P4), because it is the fastest platform to test end to end. Progress (2026-10-06): sign-in, push, pull and realtime sync, invite links and the activity history are live on [simsplit.web.app](https://simsplit.web.app) (#35–#41); App Check is in, unenforced (#45). Next: the offline R-2 build goes to Android production first, then v2.0.0 (load test, store listing, Data safety, enforce App Check), then iOS. Effort follows the plan (27 days after P4 was added; P0–P7, about 22 days, are done). Implementation: [R-3](../implementations/R-3-online-shared-groups.md). |

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
