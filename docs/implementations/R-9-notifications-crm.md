# R-9 Notifications and CRM as code — implementation plan

Status: in progress (P1 and P3 done; P2 and P4 under way)   ·   Spec: [R-9](../product/specs/R-9-notifications-crm.md)   ·   Written 2026-11-21

How R-9 gets built. One new service, `services/crm`, sends every message. Its config
lives in `crm/` in this repo. The traits that audiences select on come from a dbt model
in data-platform. The cloud resources are added in everything-as-code. The app gains
device registration, a Notifications settings screen, per-group mute and in-app banners.

## Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| One sender | `services/crm` (TypeScript on Cloud Run, like `services/telemetry`) handles event triggers, schedules and campaigns. It has its own service account; telemetry keeps its insert-only role from R-8 | Calm limits and the send ledger need one place that sees every message. Mixing this into telemetry would widen the access R-8 narrowed |
| Config baked into the image | `crm/` is validated and compiled to one JSON file at build time, and that file ships inside the `services/crm` image. Each Cloud Run revision runs exactly one config commit | Rollback means a revert or moving traffic to the previous revision. The service needs no runtime config store, and the config can't drift from git |
| Event source | One Eventarc Firestore trigger (`document.v1.created` on `groups/{g}/activity/{a}`) calls the service. The service reads the entry from Firestore by the event's document name, and the event ID dedupes it | A Firestore event does not say who wrote a document. An activity entry already carries `actorUid`, the action and before/after (deletes too), and R-8's rules validate it. One trigger covers expenses and settlements, the protobuf payload never needs decoding, and the app does not change how it writes. Eventarc is free for Google sources and needs no Cloud Functions |
| Batching | The first event in a group starts a Cloud Tasks task due when `batch_window` ends; later events in that window go into one pending document (`crm_pending/{groupId}`) | One message per window per recipient (AC7). Cloud Tasks is free under 1 M operations a month |
| Schedules and campaigns | One Cloud Scheduler job calls `/tick` every 15 minutes. The tick sends whatever the config says is due, using each device's stored time zone | Scheduler's free tier is 3 jobs, so one tick avoids a Terraform resource per campaign, and it gives local-time delivery (AC11, AC14) |
| Ledger | `crm_ledger/{uid}` records the last non-group send and the quiet-hour queue; `crm_sends/{messageId}/devices/{deviceId}` makes every send idempotent. These collections are server-only (the rules deny clients) | Caps and at-most-once delivery hold across retries and re-applies (AC13, AC19) |
| Preferences are authoritative at send time | The service reads `users/{uid}.notificationPrefs`, group mutes and devices from Firestore for every recipient. Traits only pick the candidates | Traits are up to a day old, while a switch the user just turned off must win (AC22) |
| Traits | data-platform builds the dbt model `simsplit_crm.user_traits`: one row per existing uid, with the dbt contract enforced. Only this dataset is shared with the crm service account (`roles/bigquery.dataViewer` on the dataset, plus `jobUser` in the simsplit project). `crm/traits.yaml` lists the columns, and the dev deploy job checks it against the table's schema before deploying | Audiences without SQL (AC20). The crm service sees traits only, never names, emails or raw events. A deleted account's row disappears on the next daily run |
| Audience compiler | `crm/audiences/*.yaml` hold `all`/`any` rules with one level of nesting. The compiler validates them against `traits.yaml` and emits one parameterised query with `maximumBytesBilled` | No injection is possible, the cost per query is bounded, and the rules read as plain words in a PR (AC17) |
| Prd path | `crm_deploy.yml` builds the image once, deploys it to dev, then its prd job waits in one new GitHub Environment, `crm-prd` (maintainer approval, `main` only), and deploys the same image digest. Workload Identity for `crm-prd` can only deploy `simsplit-crm` | App deploys stay tag-only (R-5), while a typo in a notice doesn't need an app release. One approval, and prd runs exactly what dev ran |
| No audience counts | Neither the PR nor the approval counts audiences; the PR shows the rules in plain words and the rendered messages. Dev shows what users get | Counting on prd before approval would need a second, read-only prd identity; the calm limits cap the damage of a too-wide audience anyway |
| Campaign timing | On dev, a campaign goes out at the next tick after deploy, so it can be checked on SimSplit [Dev]. On prd it follows `send_at`; approved after `send_at` but before `ends_at`, it goes out at the next tick; after `ends_at`, never. `crm validate` warns when `send_at` is less than an hour after the PR is opened | Dev is for looking at the real message; prd timing stays what the PR says |
| Rollback | Revert the PR (same path), or a one-line `kill_switch: true` PR; in an emergency, move Cloud Run traffic to the previous revision in the console | Every revision is one config commit |
| Android channels | One channel per category, named in EN/VI, and created on first launch after update | The system settings mirror the app's switches (AC5) |
| Web push | `firebase_messaging` on web with `firebase-messaging-sw.js`. The VAPID key is public config. The CSP report-only list from R-8 adds `fcmregistrations.googleapis.com` | The web app is half the users. R-8's CSP must not block it once enforced |
| Measurement | The service writes one row per send to `simsplit_raw.crm_sends` (insert-only role, as for telemetry). The app logs a `notification_opened` usage event with the message ID. dbt adds `fct_crm_sends` and an Evidence page | AC24 without a new pipeline |

## Architecture

```
crm/ (YAML) ──build──► services/crm image (config.json baked in)
                           │
activity entry ─Eventarc─►│/events ──► crm_pending + Cloud Tasks ──►│/flush ─┐
Cloud Scheduler 15' ──────►│/tick   ──► due schedules & campaigns ──────────┤
                           │              audience → BigQuery user_traits     │
                           ▼                                                  ▼
            prefs, mutes, devices (Firestore) ─► calm limits + ledger ─► FCM / announcements/{id}
                                                                         └► simsplit_raw.crm_sends
```

```
crm/
  policy.yaml        quiet hours, caps, kill_switch
  categories.yaml    id, default, EN/VI name + description (codegen → app + Android channels)
  traits.yaml        catalog: name, type, column, operators
  triggers/*.yaml    event → recipients, batch_window, template, rollout %
  schedules/*.yaml   cron (device time), audience, template
  campaigns/*.yaml   send_at, ends_at, audience, channels (push | inapp), template
  audiences/*.yaml   all/any rules over traits
  templates/*.yaml   push and banner copy, EN + VI, declared variables, batched variant
```

The `crm` CLI lives in `services/crm` and has three commands:

- `validate`: checks the schema, both languages, variables, lengths, references and calm limits (AC16).
- `render`: produces a Markdown preview of every message with sample data.
- `plan`: diffs the compiled config against `crm/` on `main`, offline.

The PR check posts `render` and the diff as a comment.

### Libraries

The core is a pipeline of pure functions. Firestore, FCM, BigQuery and Cloud Tasks sit
behind interfaces, so the unit tests need no cloud:

event or tick → pick trigger / schedule / campaign → candidates → filter (prefs, mutes,
permission, devices) → calm policy → render per locale → send → ledger and `crm_sends`.

| Need | Library | Why |
| --- | --- | --- |
| Firestore, FCM | `firebase-admin` | Already used by telemetry. `messaging().sendEach()` sends to many devices in one call |
| `crm_sends` rows | `@google-cloud/bigquery-storage` | Same write path as telemetry. The Storage Write API is free, while streaming inserts are billed |
| Audience queries | `@google-cloud/bigquery` | Parameterised queries with `maximumBytesBilled` |
| Batch flush | `@google-cloud/tasks` | Delayed tasks |
| YAML | `yaml` | Errors carry line numbers for the PR check |
| Config schema | `zod` (v4) | One schema gives the TypeScript types, the validation and a JSON Schema (`z.toJSONSchema`) for editor completion in `crm/` |
| Templates | `intl-messageformat` | ICU syntax, the same as the app's ARB files, plurals included |
| Cron in device time | `cron-parser` | Time zone support |
| CLI, HTTP, tests | `node:util` `parseArgs`, `node:http`, `node:test` | Built in, as in telemetry |
| PR comment | `gh pr comment --edit-last` | No third-party action (R-8 supply chain) |

Eventarc, Cloud Tasks and Scheduler call the service with OIDC tokens checked by Cloud Run
IAM, so no auth library. Self-hosting Novu was ruled out: it needs MongoDB and Redis
running (not zero cost), and the calm limits would still be ours to write.

On the app side:

- `firebase_messaging` handles push.
- `flutter_timezone` provides the IANA time zone name.
- About 20 lines of Kotlin create the Android channels, instead of using `flutter_local_notifications`.
- A small Dart script generates the category enum from `crm/categories.yaml`. The category names stay in the ARB files.

A push that arrives while the app is in the foreground is not shown, because the group
already updates live.

### App data (Firestore)

| Path | Fields | Rules |
| --- | --- | --- |
| `users/{uid}/devices/{deviceId}` | `token`, `platform`, `locale`, `tzOffsetMinutes`, `tzName`, `appVersion`, `updatedAt` | owner only; bounded strings |
| `users/{uid}.notificationPrefs` | `groupActivity`, `settleReminder`, `updates` (bool), `mutedGroups` (≤ 200 IDs) | owner only |
| `announcements/{id}` | banner copy EN/VI, `audienceUids` or `all`, `endsAt` | signed-in read (own audience), server write |
| `crm_*` | server state | no client access |

A deleted account loses `users/{uid}`, including its devices. Signing out deletes the
device document before Auth signs out (AC23).

## Phases

| Phase | Repo | Scope | ACs | Effort |
| --- | --- | --- | --- | --- |
| P1 Foundation | sim-split, everything-as-code | `crm/` schemas and starter files; `services/crm` CLI (`validate`, `render`, `plan`) with tests; PR check and comment; `crm_deploy.yml` (dev on merge, then prd behind `crm-prd`); the service skeleton (`/events`, `/flush`, `/tick` return 204, kill switch). Infra on dev and prd: Cloud Run service (min 0, max 1), service account, Eventarc triggers, Cloud Tasks queue, Scheduler tick, `crm-prd` environment and WIF binding | AC15–AC17, AC18 (dev) | 3 days |
| P2 Devices and settings | sim-split | `firebase_messaging` on Android and web; device registration and token refresh; permission timing (AC1–AC2); Settings → Notifications; group Mute; Android channels; tap → deep link; usage events; rules and emulator tests for `devices` and prefs. Privacy policy, Data safety and strategy updated in the same release (AC25) | AC1–AC5, AC8, AC23, AC25 | 3 days |
| P3 Group activity | sim-split | Trigger on activity entries for expenses and settlements (create, edit, delete); batching; recipients (members except actor, not muted, not archived); localisation and money formatting shared with the app's rules (golden tests against `MoneyFormatter` output); FCM send, removal of invalid tokens; quiet hours (held back in `crm_deferred`, delivered by the tick) and ledger | AC6–AC10, AC14, AC19 | 3 days |
| P4 Traits and audiences | data-platform, sim-split, everything-as-code | dbt `user_traits` (platform, language, app version, signup days, last active days, sessions 30 d, open groups, multi-member groups, owes / owed, oldest unsettled days, prefs); dataset `simsplit_crm` and its grant; `traits.yaml`; audience compiler with tests; freshness guard and alert | AC20–AC22 | 2.5 days |
| P5 Campaigns | sim-split | Campaigns over `/tick` (dev: next tick, prd: `send_at`); in-app banner (home screen, one at a time, dismiss syncs per account); push campaigns under the weekly cap; `simsplit_raw.crm_sends` rows; `fct_crm_sends` + Evidence page | AC12, AC13, AC18, AC24 | 2.5 days |
| P6 Settle reminders | sim-split | `settle-reminder` schedule (Sunday 19:00 device time), audience `owes-14d`, total and count across groups, tap → settle screen | AC11 | 1 day |
| P7 Email | sim-split, everything-as-code | Account and policy emails only, once the sender is chosen (spec open question) | — | 2 days |

Done so far: P1 infrastructure in everything-as-code #259 (dev and prd), P1 code in
this repo (`crm/`, `services/crm`, the CRM config check and `crm_deploy.yml`). P3 in
everything-as-code #260 (Firestore and FCM roles) and this repo: group activity batched
per group, sent to the other members' devices, held back in quiet hours; the money
format is shared with the app through `services/crm/test/money_vectors.json`. P4 in
everything-as-code #261 (dataset `simsplit_crm`, grants, error alert), data-platform
(`user_traits`) and this repo: the trait catalog, the audience compiler (parameterised
BigQuery), the catalog check in the dev deploy and the 36-hour freshness rule.

P2 must ship to production before any production send is configured. P3 needs P1 and
P2. P4 can run in parallel with P3. P5 and P6 need P4. Total about 17 days.

## Manual steps

- P1: Firebase console → Cloud Messaging: create the Web Push certificate (VAPID) for each
  project and put the public key in the app's env config.
- P1: create the `crm-prd` environment with the maintainer as required reviewer (in
  `terraform/github`, if the provider supports it there, else by hand).
- P2: Play Console → Data safety: add Device or other IDs (token) and App activity (for
  notifications); mirror the change in `data_safety.csv`.
- P3 and P5: test on dev with two accounts, two devices and the web app, including quiet
  hours (set the device clock) and Mute.

## Risks

| Risk | Mitigation |
| --- | --- |
| A wrong rule or template spams real users | Dev first, with the same image; prd behind one approval; caps enforced in code, not config; kill switch; `rollout` % on triggers |
| Eventarc delivers twice or out of order | Pending items keyed by the activity entry ID, which the event names; a batch reads the entries from Firestore, not event payloads |
| Notifications hurt Calm (users mute everything) | Group activity batched, others opt-in, quiet hours; success check tracks mute rate; adjust defaults before widening |
| Cross-project BigQuery access leaks more than traits | Grant on the `simsplit_crm` dataset only; the traits model has no names or emails; R-8 security review in PR mode for P1 and P4 |
| CSP enforcement (R-8 follow-up) blocks web push | P2 adds FCM origins to the report-only CSP and watches reports before R-8 enforces it |
| Old app builds have no device registration | They get nothing; banners and push start with the release that ships P2 |
