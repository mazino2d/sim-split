# R-4 Error reports and usage analytics — implementation plan

Status: in progress (P0–P2 done)   ·   Spec: [R-4 Error reports and usage analytics](../product/specs/R-4-error-reports-and-usage-analytics.md)   ·   Written 2026-10-23

How R-4 gets built: the architecture, the phases (one or two PRs each) and the decisions
behind them. The spec defines *what* must be true. This plan defines *how* and in what
order. Work spans three repos: this one (app, endpoint, rules), `everything-as-code`
(infrastructure) and `data-platform` (ingestion, dbt models and the dashboard).

## Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Endpoint | One Cloud Run service, `telemetry`, in `simsplit-as-se1-prd` (`asia-southeast1`), written in TypeScript, code in `services/telemetry/` here | Same project as App Check and Auth, so it verifies their tokens with `firebase-admin` and the existing budget and kill switch cover it. TypeScript has the two libraries it needs in their most complete form: `firebase-admin` (App Check and ID token verification) and the BigQuery Storage Write API `JSONWriter`. The code lives next to the app because its schema changes with the app's events. |
| Fan-out | The endpoint logs each accepted report as one structured JSON line on stdout (Cloud Run ships it to Cloud Logging) and appends the same record to BigQuery | stdout costs nothing extra and needs no Logging API calls. The BigQuery write is the copy kept indefinitely; Logging is for alerts and the last 30 days. |
| BigQuery write path | Storage Write API, default stream, through `JSONWriter` | Free up to 2 TiB a month. Legacy streaming inserts (`insertAll`) are billed and are never used (AC22). |
| Warehouse location | Dataset `simsplit_raw` in `dataplatform-as-se1-prd`, created by Terraform; the endpoint's service account gets `bigquery.dataEditor` on that dataset only | The maintainer's one warehouse (data-platform). The dataset name follows data-platform's `<source>_raw` convention, so dbt reads it like any other source. |
| Tables | `error_reports` and `usage_events`, partitioned by day on `received_at`, clustered by `report_id` and `uid`, no partition expiration | Kept indefinitely (AC18); partitions and clustering keep the maintainer's queries inside the free query tier. |
| Group data copy | A dlt source in data-platform reads Firestore (`groups` and the collection groups `members`, `expenses`, `settlements`, `activity`) incrementally on `updatedAt` (`syncedAt` for activity) into `simsplit_raw`, once a day | Reads only what changed, so Firestore reads stay far below the free 50,000 a day. Runs on data-platform's existing DAG workflows. |
| User data and consent | A Firestore document `users/{uid}` holds `displayName`, `email`, `createdAt` and `consent {agreedAt, policyVersion}`; created by the app on the first sign-in (that is the agreement, AC7), deleted with the account | Gives the rules a server-side record of the agreement and is the source of `dim_user`. Rules make the consent fields immutable. |
| Deleting a user from the warehouse | dlt loads `users` with `write_disposition=replace` every run, and `dim_user` is a plain table built from it (no snapshot) | A deleted account's document disappears from Firestore, so the next daily load drops it from raw and from `dim_user` with no extra purge job (AC11). The dataset's time travel is set to the 48-hour minimum (see risks). |
| Agreement | No consent screen: the sign-in screen gets one line linking the privacy policy (AC6), and the sign-in use case creates `users/{uid}` with `consent.agreedAt` (server time) and the policy version when the document does not exist yet; if that write fails, the sign-in fails and the user retries | Signing in is the agreement, so there is no gate, no decline path and no extra route. |
| Rules enforce consent | Every group read and write requires `exists(/databases/$(database)/documents/users/$(request.auth.uid))` | An installed 2026.10.22 build never writes `users/{uid}`; after the account wipe it could sign in again and sync without agreeing. The rule makes such a build unable to read or write groups. |
| Client queue | A Drift table `telemetry_queue` (schema v5): kind, JSON payload, created time; capped per kind, oldest dropped | Survives restarts and works offline (AC13) with the storage the app already has. |
| Sending | Usage events in batches (at most one request a minute, plus one on going to the background); error reports right away. App Check token from `getToken()` (cached), never `getLimitedUseToken()`; ID token only on usage batches | On web each fresh App Check token costs a reCAPTCHA assessment; the cached 24-hour token keeps assessments at R-3's level. |
| Scrubbing | In the app before queueing, and again in the endpoint: emails, Firestore paths and document IDs, UUIDs, invite tokens, digit runs and the current user's names and group names are replaced by placeholders; breadcrumbs only ever hold route patterns and action names from a fixed enum | Free text never enters a report, so AC4 holds even if an error message quotes data. The endpoint pass is a second line of defence. |
| Event names | A Dart enum `UsageEvent` holds every name (`tap_add_expense`, `submit_expense_form`, `op_save_expense`, …) | One fixed vocabulary for breadcrumbs (AC3) and usage events (AC8); no names or IDs can slip in. |
| Tracking every action | Automatic, in four places rather than call by call: (1) the design system's interactive widgets (buttons, list tiles, switches, tabs, chips, menu items, dialogs, sheets, forms) take a required `event` argument and record the tap, open, close, submit or abandon themselves; (2) every use case is registered in DI through a `TrackedUseCase` wrapper that records `op_<name>` with the result (`Either` right, or the `Failure` type) and the duration; (3) a `NavigatorObserver` records screens, dialogs and sheets as `GoRouterState.fullPath` patterns; (4) a custom lint plus a test that scans `lib/presentation` fail the build on a raw `onTap` / `onPressed` outside the design system or a use case not wrapped (AC8a) | New screens are tracked by construction instead of relying on someone remembering a call. |
| Sessions | A random session ID per app launch, renewed after 30 minutes in the background; sent with usage events and error reports | Sessions and "errors per 100 sessions" (AC31) need a denominator; the ID is random, so error reports stay anonymous. |
| Cost guards | Cloud Run: min 0, max 1 instance, 256 MiB, request-based billing, 10 s timeout, 64 KB body limit. Endpoint: in-memory per-install daily counters (exact with a single instance). Logging: default bucket only. Artifact Registry: keep the last 2 images | Each guard is a hard limit, so a bug or abuse hits a wall instead of the bill (AC20–AC23). |
| Alerts | A log-based alert on error reports (email, rate-limited to one notification per hour), and a Cloud Monitoring alert on `simsplit_raw` storage at 8 GiB, both in Terraform | AC19 and AC23. Alerting policy pricing must be checked before P0 merges (spec open question). |
| Dashboard | An [Evidence](https://evidence.dev) project in data-platform (`evidence/`, one folder of pages per project, `simsplit/` first), whose sources query only aggregate dbt models in `simsplit_metrics` (no uid, name or email columns). A DAG task after the marts builds it in GitHub Actions (Workload Identity Federation) and deploys the static output with `wrangler pages deploy` to a Cloudflare Pages project behind Cloudflare Access that admits only the maintainer's Google account | Evidence bakes query results into the static site, so it must not go to GitHub Pages; Cloudflare Pages direct uploads and Access (up to 50 users) are free, and the Cloudflare account is already managed in everything-as-code. Aggregate-only sources keep personal data out of the built site even behind Access. |
| Existing accounts | A one-off script in `scripts/` (Admin SDK, run by the maintainer) deletes every Auth user and all Firestore data at release time. The app treats `user-not-found` / `user-disabled` on token refresh as a forced sign-out that discards the outbox and local data | AC12. The normal sign-out refuses while changes are unsynced; a deleted account can never sync them. |

## Architecture

```
App (Flutter)
  lib/domain
    + entities: ErrorReport, UsageEvent, Breadcrumb
    + repositories: TelemetryRepository, UserProfileRepository
    + use cases: RecordError, RecordUsageEvent, SetErrorReportsEnabled,
                 WatchErrorReportSettings; SignInWithGoogle also records the agreement
  lib/data
    Drift (schema v5): telemetry_queue
    telemetry/ recorder:  session ID, breadcrumbs ring buffer (30), dedupe per session,
                          daily caps, scrubber, writes to telemetry_queue
               tracking:  TrackedUseCase wrapper (DI), design-system widgets with a
                          required event, navigator observer
               sender:    drains the queue in batches with App Check (and ID token for
                          usage), exponential backoff, silent failures
               hooks:     FlutterError.onError, PlatformDispatcher.onError, the shared
                          error-message helper (AC2), router observer, UsageAction calls
    Firebase repositories: user profile (users/{uid}, created on first sign-in)
  lib/presentation
    Sign-in screen: one line linking the privacy policy
    Settings: wrench action in the app bar → /settings/diagnostics: error report switch,
              report ID, app version and build, platform, queued reports (AC25–AC27)

Cloud Run telemetry (simsplit-as-se1-prd)
  POST /v1/errors   App Check required; body ≤ 64 KB; schema check; scrub;
                    per-install caps → stdout JSON (severity ERROR) + BigQuery
  POST /v1/events   App Check + Firebase ID token; every event's uid must equal the
                    token's uid → BigQuery (no log line)

BigQuery dataplatform-as-se1-prd
  simsplit_raw     error_reports, usage_events (from Cloud Run)
                   users (dlt, replace), groups, members, expenses, settlements,
                   activity (dlt, merge on document path)
  simsplit_*       dbt models in data-platform: staging, dim_user, fct_usage_events,
                   fct_error_reports, group facts and SCD snapshots of groups and members

Dashboard (data-platform)
  dbt simsplit_metrics   aggregate models: active users, sessions, screens and actions,
                         funnel, errors per session, operation failures and durations
  evidence/simsplit      pages on those models → static build in GitHub Actions →
                         Cloudflare Pages behind Cloudflare Access (maintainer only)

Firestore
  users/{uid}      displayName, email, createdAt, consent {agreedAt, policyVersion}
                   read/create by the owner only; consent immutable; deleted with the
                   account
```

Payloads, in short:
- Error report: `report_id`, `client_time`, `platform`, `os`, `app_version`, `language`,
  `signed_in`, `online`, `session_id`, `error_type`, `message`, `stack`, `count`,
  `breadcrumbs[]`.
  The endpoint adds `received_at`.
- Usage event: `uid`, `session_id`, `client_time`, `kind` (`screen`, `tap`, `form`,
  `dialog`, `gesture` or `op`), `name`, `screen` (route pattern), `result` and
  `duration_ms` (operations only), `platform`, `app_version`, `language`, `online`, plus
  `received_at`.

## Phases

| # | Repo | Scope | Spec ACs | Days |
| --- | --- | --- | --- | --- |
| P0 ✅ | everything-as-code | Done in everything-as-code#235. Infrastructure. simsplit stack: Artifact Registry repo (cleanup: keep 2), `telemetry` service account, Cloud Run service (limits above; image managed by CI, `ignore_changes`), public invoker, deployer role for `gha-firebase-deployer`, log-based metric and alert with an email channel. dataplatform stack: dataset `simsplit_raw` (time travel 48 h) with the two tables, `bigquery.dataEditor` on it for the `telemetry` SA, `datastore.viewer` on simsplit for `gha-data-platform`, storage alert | AC19, AC21, AC23 | 1.5 |
| P1 ✅ | sim-split | Done in #75; live at `telemetry-113980760756.asia-southeast1.run.app`. Endpoint in `services/telemetry/`: token verification, schema validation, size limit, scrub, per-install caps, stdout log, `JSONWriter` append; unit tests with fakes for Firebase and BigQuery; deploy workflow (build in GitHub Actions, push, `gcloud run deploy`) on `main` | AC18–AC22 | 2 |
| P2 ✅ | sim-split | Done in #76. Sending stays off until the `TELEMETRY_URL` repo variable is set in P5, together with the privacy policy. Error reports in the app: domain, Drift v5 queue, recorder (session ID), scrubber with the AC4 test, sender, error hooks, breadcrumbs (navigator observer, `UsageEvent`), the Diagnostics screen behind the wrench icon in Settings, EN/VI | AC1–AC5, AC13, AC15–AC17, AC25–AC29 | 3 |
| P3 | sim-split | Agreement and usage events: the policy line on the sign-in screen, `users/{uid}` created on first sign-in (rules for the collection, with tests), deleted with the account, usage events from the same `track` call as breadcrumbs, batches with the ID token, sessions renewed after 30 minutes away, and data left by a deleted account dropped instead of uploaded on the next sign-in. The rule that makes `users/{uid}` required for groups ships in P5: deployed earlier, it would lock out every current account | AC6, AC7, AC9, AC14 | 1.5 |
| P3b | sim-split | Tracking every action: event argument on every design-system interactive widget, `TrackedUseCase` in DI, every existing screen migrated, the lint and the AC8a test | AC8, AC8a | 2 |
| P4 | data-platform (+ indexes here) | `simsplit` project: dlt Firestore source (users replace, the rest incremental), collection-group indexes on `updatedAt` / `syncedAt` in `firestore.indexes.json`, dbt staging, `dim_user`, `fct_usage_events`, `fct_error_reports`, group models, DAG YAMLs | AC10, AC11, AC18 | 3 |
| P4b | data-platform + everything-as-code | Dashboard: `simsplit_metrics` aggregate models, Evidence project and `simsplit` pages, DAG task to build and deploy; Cloudflare Pages project, Access application and policy, and the deploy token as a data-platform secret (everything-as-code cloudflare and github stacks) | AC31, AC32 | 2.5 |
| P5 | sim-split | Release: the rule requiring `users/{uid}` for every group read and write (with tests), privacy policy, `data_safety.csv`, store listing, site and release notes (EN/VI) announced before rollout; the account wipe script, run when the rollout starts; verify the three known bugs produce reports and alerts; billing check after a month | AC12, AC24, AC30, success check | 2 |

The total is about 16 focused days (the roadmap uses this estimate). P0 comes first
because P1 deploys to it. P2 and P4 can run in parallel once P1 is live; P3b follows P2,
and P4b needs P4's models plus a few days of events. P3 and P3b must ship in the same
release as P5: the agreement rule, full tracking and the account wipe go out together.

## Manual steps (no API or Terraform support)

1. Confirm the email notification channel (Cloud Monitoring sends a verification email).
2. Update the Play Console Data safety form from `data_safety.csv` and submit the store
   listing with the release (P5).
3. Run the account wipe script with the maintainer's credentials when the rollout starts
   (P5), after the release notes and site have announced it.

## Risks

| Risk | Mitigation |
| --- | --- |
| Cloud Monitoring starts charging for alerting policies | Checked 2026-10-24: charges start no sooner than 2027-09-01, at $0.35 a month per policy (log-match conditions return no points). Before then, replace the two policies with a free path (for example the endpoint emailing through Pub/Sub) or accept $0.70 a month. |
| BigQuery time travel keeps a deleted user's rows readable for up to 48 hours after the daily load removes them | Accepted in AC11 and stated in the privacy policy. Time travel set to its 48-hour minimum on `simsplit_raw` (Terraform) and on every simsplit model dataset (dbt dataset config). |
| Installed 2026.10.22 builds keep running after the account wipe | Rules require `users/{uid}` for every group access, so they cannot sync; they show sync errors until updated. Play auto-updates most installs within days. |
| Users lose their groups and unsynced local data in the wipe | Announced in release notes and on the site before the rollout (AC12); accepted by the spec. |
| Tracking every tap fills the free 10 GiB of BigQuery storage, since nothing is deleted | ~100 users × ~300 events a day × ~300 bytes ≈ 3 GiB a year, shared with jaffle_shop. The 5,000-a-day cap bounds a runaway client, and the storage alert at 8 GiB is the trigger to aggregate or archive old events. |
| The Evidence build bakes query results into static files | Sources read aggregate models only, the output is deployed straight from CI to Cloudflare Pages behind Access, and it is never committed or uploaded as a public artifact. |
| Abuse floods the endpoint and the bill | App Check on every request, 64 KB limit, one instance, per-install caps, budget and kill switch on both projects. |
| A scrubber miss leaks personal data into an error report | Scrubbing twice (app and endpoint), breadcrumbs from a fixed vocabulary, and the AC4 test feeding real-looking values through an error. |
| Storage Write API default stream: rows are briefly in the streaming buffer and cannot be changed by DML | Nothing in R-4 updates or deletes these rows; `dim_user` deletion works on dlt-loaded tables. |
| Mixed release order: the app sends before the endpoint exists | P1 deploys before P2 merges; the sender treats any failure as "retry later" and drops nothing beyond the queue caps. |
