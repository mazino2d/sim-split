# SimSplit product docs

How SimSplit decides what to build and why. These pages are the source of truth for
product decisions and are maintained alongside the code.

## Strategy

- [Product strategy](strategy.md): vision, persona, objective, North Star quality bars,
  non-negotiables and non-goals.
- [Design principles](principles.md): ordered principles and what each one costs.
- [Use cases](use-cases.md): core and supporting use cases with measurable success
  criteria.
- [Roadmap](roadmap.md): product phases and the backlog, scored with RICE-lite.

## Phases

Each phase has a spec that also records its story.

| Phase | Status | Summary |
| --- | --- | --- |
| [R-1 Offline app (v1.0)](specs/R-1-offline-app.md) | Shipped | The first app: offline, no account, one bookkeeper logs for the group. [Implementation](../implementations/R-1-offline-app.md). |
| [R-2 UX polish and strategy clarity](specs/R-2-ux-polish-and-strategy.md) | Shipped | Faster expense and group flows, a monochrome redesign, and the strategy written down. [Implementation](../implementations/R-2-ux-polish-and-strategy.md). |
| [R-3 Co-worked groups](specs/R-3-online-shared-groups.md) | In progress | Friends log expenses together with full trust; every change is auditable. Google sign-in, realtime sync, invite links and the activity history are live on [the web app](https://simsplit.web.app); Android release (v2.0.0) and iOS follow. [Implementation](../implementations/R-3-online-shared-groups.md). |
| [R-4 Anonymous error reports](specs/R-4-anonymous-error-reports.md) | Planned | The app reports errors and the steps that led to them, with no account, names or amounts, so testers' bugs can be fixed. On by default, off switch in Settings; ships before v2.0.0. |

[← Back to SimSplit](../)
