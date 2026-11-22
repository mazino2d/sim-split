# R-9 Notifications and CRM as code — implementation plan

Status: in progress (P1–P4, P6 and P5 except the dashboard done)   ·   Spec: [R-9](../product/specs/R-9-notifications-crm.md)   ·   Written 2026-11-21

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
| Prd path | A repo admin comments `crm apply` on the PR: `crm_apply.yml` checks the PR is green and from this repo, squash-merges it and calls `crm_deploy.yml`, which builds the image once and deploys the same digest to dev, then prd (environment `prd`, no approval step). A plain merge deploys dev only. Changed 2026-11-22 from a `crm-prd` environment with a required reviewer | Approving in the Actions UI was awkward on a phone; a PR comment is not. A typo in a notice doesn't need an app release, and prd runs exactly what dev ran. App deploys still check their `vYYYY.M.D` tag |
| No audience counts | Neither the PR nor `crm apply` counts audiences; the PR shows the rules in plain words and the rendered messages. Dev shows what users get | Counting on prd before applying would need a second, read-only prd identity; the calm limits cap the damage of a too-wide audience anyway |
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
- The app's `NotificationCategory` enum and the ARB names and descriptions mirror `crm/categories.yaml`; a unit test parses the YAML and fails when the ids, defaults or EN/VI copy differ (simpler than a generator for three entries).

A push that arrives while the app is in the foreground is not shown, because the group
already updates live.

### App data (Firestore)

| Path | Fields | Rules |
| --- | --- | --- |
| `users/{uid}/devices/{deviceId}` | `token`, `platform`, `locale`, `tzOffsetMinutes`, `tzName`, `appVersion`, `updatedAt` | owner only; bounded strings |
| `users/{uid}.notificationPrefs` | `groupActivity`, `settleReminder`, `updates` (bool), `mutedGroups` (≤ 200 IDs) | owner only |
| `users/{uid}.dismissedAnnouncements` | announcement ids (≤ 100) | owner only |
| `announcements/{id}` | banner copy EN/VI, `audienceUids` or `all`, `endsAt` | signed-in read (own audience), server write |
| `crm_*` | server state | no client access |

Deleting `users/{uid}` does not delete its `devices` subcollection, so account deletion
deletes every device document before the profile, and signing out deletes this install's
device document (and its FCM token) before Auth signs out; a failure there is logged and
doesn't block the sign-out (AC23). `deviceId` is a random ID made once per install, not
the R-4 error report ID. `notificationPrefs` fields are optional: a missing one is the
category's default. The `route` data of a message is `/groups/<groupId>`,
`/groups/<groupId>/expenses/<expenseId>` or `/groups/<groupId>/settle` (settlements link
to the group, which has no settlement screen); the app ignores anything else. On the web,
the sender sets `webpush.fcm_options.link` to the web app's origin plus that route.

## Phases

| Phase | Repo | Scope | ACs | Effort |
| --- | --- | --- | --- | --- |
| P1 Foundation | sim-split, everything-as-code | `crm/` schemas and starter files; `services/crm` CLI (`validate`, `render`, `plan`) with tests; PR check and comment; `crm_deploy.yml` (dev on merge; prd through `crm_apply.yml` since 2026-11-22); the service skeleton (`/events`, `/flush`, `/tick` return 204, kill switch). Infra on dev and prd: Cloud Run service (min 0, max 1), service account, Eventarc triggers, Cloud Tasks queue, Scheduler tick, deploy environment and WIF binding | AC15–AC17, AC18 (dev) | 3 days |
| P2 Devices and settings | sim-split | `firebase_messaging` on Android and web; device registration and token refresh; permission timing (AC1–AC2); Settings → Notifications; group Mute; Android channels; tap → deep link; usage events; rules and emulator tests for `devices` and prefs. Privacy policy, Data safety and strategy updated in the same release (AC25) | AC1–AC5, AC8, AC23, AC25 | 3 days |
| P3 Group activity | sim-split | Trigger on activity entries for expenses and settlements (create, edit, delete); batching; recipients (members except actor, not muted, not archived); localisation and money formatting shared with the app's rules (golden tests against `MoneyFormatter` output); FCM send, removal of invalid tokens; quiet hours (held back in `crm_deferred`, delivered by the tick) and ledger | AC6–AC10, AC14, AC19 | 3 days |
| P4 Traits and audiences | data-platform, sim-split, everything-as-code | dbt `user_traits` (platform, language, app version, signup days, last active days, sessions 30 d, open groups, multi-member groups, owes / owed, oldest unsettled days, prefs); dataset `simsplit_crm` and its grant; `traits.yaml`; audience compiler with tests; freshness guard and alert | AC20–AC22 | 2.5 days |
| P5 Campaigns | sim-split | Campaigns over `/tick` (dev: next tick, prd: `send_at`); in-app banner (home screen, one at a time, dismiss syncs per account); push campaigns under the weekly cap; `simsplit_raw.crm_sends` rows; `fct_crm_sends` + Evidence page | AC12, AC13, AC18, AC24 | 2.5 days |
| P6 Settle reminders | sim-split | `settle-reminder` schedule (Sunday 19:00 device time), audience `owes-14d`, total and count across groups, tap → settle screen | AC11 | 1 day |
| P7 Email | sim-split, everything-as-code | Account and policy emails only, once the sender is chosen (spec open question) | — | 2 days |
| P8 Settings v2 | sim-split, everything-as-code | More control with the same calm defaults: see § P8 below (P8a sender, P8b screens) | AC26–AC35 | 4.5 days |

Done so far: P1 infrastructure in everything-as-code #259 (dev and prd), P1 code in
this repo (`crm/`, `services/crm`, the CRM config check and `crm_deploy.yml`). P3 in
everything-as-code #260 (Firestore and FCM roles) and this repo: group activity batched
per group, sent to the other members' devices, held back in quiet hours; the money
format is shared with the app through `services/crm/test/money_vectors.json`. P4 in
everything-as-code #261 (dataset `simsplit_crm`, grants, error alert), data-platform
(`user_traits`) and this repo: the trait catalog, the audience compiler (parameterised
BigQuery), the catalog check in the dev deploy and the 36-hour freshness rule.
P5 and P6 server side in this repo: the tick runs schedules (in each device's clock,
amounts worked out from Firestore at send time) and campaigns (in-app announcements
in `announcements/{id}`, pushes for Updates), with the weekly cap in `crm_ledger`.
P5 app side: the in-app banner on the home screen (one at a time, the one ending
first; tap shows the whole text; dismissing it is kept in
`users/{uid}.dismissedAnnouncements`, at most 100, for every device of the account), the
rules for `announcements` (read when `all` or the reader is in `audienceUids`, no client
writes) and their two composite indexes, and usage events `op_announcement_shown`,
`tap_announcement`, `tap_dismiss_announcement` and `op_dismiss_announcement` whose
result is `campaign_<id>`. `op_notification_opened` now records the message's `source`
data (`trigger:<id>`, `schedule:<id>` or `campaign:<id>`) as `<kind>_<id>`, which gives
per-message open counts (AC24). Left in P5: the dashboard.
P2 in this
repo: `firebase_messaging` and `flutter_timezone`; device registration
(`lib/data/notifications/`) on sign-in, app start, language change and token refresh,
only after the user tapped Turn on and the system allows it; the one-time inline card in
a group with another account; Settings → Notifications; Mute in the group menu with a
muted mark; Android channels from `MainActivity.kt`; tap → deep link (`getInitialMessage`,
`onMessageOpenedApp`, and on the web the link kept through sign-in); usage events
`op_notification_permission`, `op_set_notification_pref`, `op_mute_group`,
`op_unmute_group`, `op_register_device`, `op_notification_opened` (the message ID embeds a
group ID, so it stays out of usage events); rules and emulator
tests for `devices` and `notificationPrefs`; `web/firebase-messaging-sw.js` (config from
Hosting's `/__/firebase/init.js`) and `FCM_VAPID_KEY` in `firebase_deploy.yml`; privacy
policy, Data safety and strategy updated (AC25).

P2 must ship to production before any production send is configured. P3 needs P1 and
P2. P4 can run in parallel with P3. P5 and P6 need P4. Total about 17 days.

## P8 Notification settings v2 (design, 2026-11-22)

Spec AC26–AC35. Today the screen is three switches plus Mute in the group menu. P8
keeps that first screen as the entry point and moves the new choices one level
down, so the defaults stay one glance away and nothing gets louder by itself.

### Screens

```
Settings → Notifications                     Group activity
┌──────────────────────────────────┐        ┌──────────────────────────────────┐
│ Pause notifications       Off  › │        │ Group activity               [●] │
│                                  │        │                                  │
│ Group activity           [●]  › │──────► │ NOTIFY ME ABOUT                  │
│  Every 10 min · all changes      │        │ New expenses                 [●] │
│ Settle reminders         [ ]  › │        │ Edited expenses              [●] │
│  Off                             │        │ Deleted expenses             [●] │
│ Updates                  [ ]     │        │ Settlements                  [●] │
│  Rare news about SimSplit        │        │ Members joining              [ ] │
│                                  │        │ Only changes that involve me [ ] │
│ Quiet hours   21:00 – 08:00   › │        │                                  │
│ Groups                        › │        │ BUNDLE CHANGES                   │
│                                  │        │ (•) Every 10 minutes             │
│ Send a test notification         │        │ ( ) Every 30 minutes             │
│ ⓘ Notifications are on for this  │        │ ( ) Every hour                   │
│   device.                        │        │ ( ) Once a day at 19:00          │
└──────────────────────────────────┘        └──────────────────────────────────┘

Settle reminders (when on)                   Groups / group menu → Notifications
┌──────────────────────────────────┐        ┌──────────────────────────────────┐
│ Settle reminders             [●] │        │ Đi Đà Lạt                        │
│ Day          Sunday           › │        │ (•) All activity                 │
│ Time         19:00            › │        │ ( ) Only changes that involve me │
│ Remind when a debt is older than │        │ ( ) Off until tomorrow 08:00     │
│ ( ) 7 days (•) 14 days ( ) 30 d  │        │ ( ) Off                          │
└──────────────────────────────────┘        └──────────────────────────────────┘
```

- Rows show their current choice as a subtitle, so the first screen still reads at a
  glance. A paused state shows "Paused until 08:00 · Resume" at the top.
- Quiet hours open a sheet with two time pickers limited to the allowed range
  (start 12:00–21:00, end 08:00–12:00).
- The group's bell-off mark stays for "Off" and "Off until …"; "Only changes that
  involve me" shows no mark.
- Pause uses a short list (1 hour, until tomorrow 08:00, 1 week); the subtitle
  shows the end time.

### Data (`users/{uid}.notificationPrefs`, version 2)

| Field | Type | Default | Note |
| --- | --- | --- | --- |
| `groupActivity`, `settleReminder`, `updates` | bool | on, off, off | unchanged |
| `activityEvents` | map of bool: `expenseCreate`, `expenseUpdate`, `expenseDelete`, `settlement`, `memberJoin` | all on, `memberJoin` off | AC26 |
| `onlyInvolvingMe` | bool | false | AC27 |
| `bundle` | `10m`, `30m`, `1h`, `daily` | `10m` | AC28 |
| `groups` | map groupId → `{ mode: all, involving or off, offUntil?: Timestamp }`, at most 200 | `all` | AC29; replaces `mutedGroups`, which the app migrates (muted → `off`) and the sender still reads until every build has moved |
| `pausedUntil` | Timestamp | absent | AC30 |
| `quietHours` | `{ from: "HH:MM", to: "HH:MM" }` | absent = policy | AC31; rules and sender enforce "at least 21:00–08:00" |
| `settle` | `{ day: 0–6, time: "HH:MM", minDays: 7, 14 or 30 }` | Sunday, 19:00, 14 | AC32 |

The rules validate every field's type, enum and bounds, as they do for today's prefs.
A missing field is its default, so old builds and old documents keep working.

### Sender (`services/crm`)

- **Activity:** filter each recipient's items by `activityEvents` and, when
  `onlyInvolvingMe`, by their member being the payer, in the splits, or a settlement
  party. The activity entry's snapshot already holds `paidByMemberId`, `splits`,
  `fromMemberId` and `toMemberId`. The `group-activity` trigger adds `member`/`join`
  to its events, and the prefs gate it (default off).
- **Bundling:** the group batch stays 10 minutes. A recipient with `30m`, `1h` or
  `daily` gets the items held in `crm_deferred` (merged per group, as quiet hours do)
  with `deliverAfter` set to their window or the next 19:00. The tick delivers them,
  one summary per group.
- **Pause and per-group off-until:** checked at send time. Group activity during a
  pause is held until `pausedUntil`; other kinds are dropped.
- **Quiet hours:** `max(policy, user)`; `calm.ts` limits stay the floor.
- **Settle reminders:** the user's `settle` replaces the schedule's cron for that
  user (the config's cron stays the default), and `minDays` filters the live debts.
  The weekly cap is unchanged.
- **Test notification (AC33):** the app sets `testRequestedAt` on its device
  document. A second Eventarc trigger on `users/{uid}/devices/{deviceId}` calls
  `/events`, which sends one push if the request is under a minute old and the
  device's last test is over 10 minutes old (ledger in `crm_ledger`).
- `crm/categories.yaml` gains the event kinds and their defaults, and the codegen and
  the category test in the app check them like the categories.

### Phases

| Phase | Repo | Scope | ACs | Effort |
| --- | --- | --- | --- | --- |
| P8a Prefs and sender | sim-split, everything-as-code | Prefs v2 in rules with emulator tests; `crm/categories.yaml` events; sender filters (events, involvement, bundle, pause, per-group modes, quiet hours, settle prefs); test-notification trigger (Eventarc on devices) and ledger; unit tests for each | AC26–AC34 (server) | 2 days |
| P8b Screens | sim-split | Settings → Notifications redesign, Group activity, Settle reminders, Groups, quiet hours sheet, pause, test button; group menu modes; migration from `mutedGroups`; EN/VI copy; widget tests; usage events for every choice | AC26–AC35 (app) | 2.5 days |

P8a ships first: the sender honours v2 fields, and old builds keep working because
every new field has a default. P8b then writes them.

## Manual steps

- P1: Firebase console → Cloud Messaging: create the Web Push certificate (VAPID) for each
  project and put the public key in the app's env config.
- P1: the deploy environment is in `terraform/github` (since 2026-11-22 the shared
  `prd`, with no reviewer).
- P2: Play Console → Data safety: add Device or other IDs (token) and App activity (for
  notifications); mirror the change in `data_safety.csv`.
- P3 and P5: test on dev with two accounts, two devices and the web app, including quiet
  hours (set the device clock) and Mute.

## Risks

| Risk | Mitigation |
| --- | --- |
| A wrong rule or template spams real users | Dev first, with the same image; prd only on an admin's `crm apply` after a green plan; caps enforced in code, not config; kill switch; `rollout` % on triggers |
| Eventarc delivers twice or out of order | Pending items keyed by the activity entry ID, which the event names; a batch reads the entries from Firestore, not event payloads |
| Notifications hurt Calm (users mute everything) | Group activity batched, others opt-in, quiet hours; success check tracks mute rate; adjust defaults before widening |
| Cross-project BigQuery access leaks more than traits | Grant on the `simsplit_crm` dataset only; the traits model has no names or emails; R-8 security review in PR mode for P1 and P4 |
| CSP enforcement (R-8 follow-up) blocks web push | P2 added the FCM origins to the CSP while it was report-only; web push was among the flows checked before R-8 enforced it |
| Old app builds have no device registration | They get nothing; banners and push start with the release that ships P2 |
