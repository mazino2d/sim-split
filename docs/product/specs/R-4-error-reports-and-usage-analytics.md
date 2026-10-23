# R-4 Error reports and usage analytics

Status: ready   ·   Serves: UC-6, UC-7, all UCs   ·   Roadmap: Now

## Problem

Friends testing the web and Android builds hit small bugs and describe them afterwards in
chat: sign-in says it failed although it worked, sign-in does not work inside some apps'
in-app browsers, and creating a group does not open it. From a description alone the
maintainer cannot tell what happened, on which platform or in what order, so the bugs
stay unfixed and trust in the app erodes.

Beyond bugs, the roadmap is prioritised on dogfooding and a handful of testers. Without
knowing which screens and actions people actually use, and how often errors happen per
session, there is no denominator for error rates and no evidence for what to build next.

The app should record what went wrong and the steps that led to it without the tester
doing anything, record how every account uses the app, and copy group data to the
maintainer's warehouse for analysis. Usage tracking is a condition of using the app, made
clear before the account is created. All of it must cost nothing to run.

## Decisions (2026-10-08, revised 2026-10-23)

| Topic | Decision |
| --- | --- |
| Pipeline | The app sends error reports and usage events to one endpoint of its own (a Cloud Run service in the app's Google Cloud project). The endpoint writes each one to two places: Cloud Logging, for alerts, and the maintainer's BigQuery warehouse ([data-platform](https://github.com/mazino2d/data-platform), modelled with dbt), for analysis. No third-party SDK (Crashlytics, Google Analytics for Firebase, PostHog and Mixpanel were ruled out). |
| Retention | Kept indefinitely in BigQuery; there is no plan to delete them. Cloud Logging keeps its default 30 days, since it only serves alerts. The one exception is account deletion (below). |
| Alerts | From Cloud Logging only: log-based alerts email the maintainer. No paging service. |
| Dashboard | Built with [Evidence](https://evidence.dev) on top of the dbt models in data-platform, refreshed daily after the pipeline, and visible only to the maintainer. |
| Zero cost | Enforced by hard limits, not by watching the bill: App Check on the endpoint, size and rate caps, an endpoint that scales to zero with at most one instance, the free BigQuery write path, and the existing budget and kill switch (AC20–AC24). |
| Error reports | Anonymous and on by default, with an off switch on the Diagnostics screen (opt-out). Acceptable only because they are anonymous: errors plus breadcrumbs, platform and app version, never the account, email, uid, group or member names, expense descriptions or amounts. Errors before sign-in are reported too. |
| Usage analytics | Per user and **required**: every action in the app — every screen, tap, form, dialog and operation with its result and duration — linked to the account's uid. Agreeing to it is a condition of using the app; there is no way to use the app without it. |
| Consent | Part of the product policy, like terms of service: the sign-in screen says in one line that continuing means agreeing to the privacy policy, which links to it; the policy describes the usage tracking and the group data copy. Signing in is agreeing — there is no separate consent screen. The agreement time and the policy version are stored when the account is created. It cannot be turned off later; deleting the account is the way out. |
| Group data copy | Every account's records (groups, members, expenses, settlements, activity) are copied to the warehouse. |
| Account deletion | Deleting an account deletes the user's row in the warehouse's user dimension (`dim_user`: name, email, consent), including its history. Fact rows (usage events, copied group records) are kept, keyed only by the uid, which no longer resolves to a person. |
| Existing accounts | Every account created before R-4 ships never agreed to the new policy, so all of them and their cloud data are deleted when R-4 ships. Everyone signs in again, which records their agreement. |
| Report ID | Each install has a random report ID, shown on the Diagnostics screen, that a tester can quote to the maintainer. It is not linked to the account. |
| Diagnostics screen | Debug details stay out of the main Settings list: a wrench icon in the Settings app bar opens a Diagnostics screen with the error report switch, the report ID and other debug details. Keeps Settings clean for everyone; testers who need it know where to tap. |
| Notice | The one line on the sign-in screen and the privacy policy behind it — no banner, dialog or consent screen (Calm). Error reports are also explained next to their switch on the Diagnostics screen. |
| Turning off | Error reports only: stops recording and sending, and deletes what is still waiting on the device. Data already sent is kept. |

## User stories

- As a tester who hit a bug, I tell the maintainer my report ID and what I was doing, so
  they can see exactly what went wrong without asking me to reproduce it.
- As the maintainer, I get an email when errors arrive, and I open the reports for a
  report ID, platform or app version and see the error with the screens and actions that
  led to it.
- As a new user, I can open the privacy policy from the sign-in screen to see what is
  collected before I sign in.
- As the maintainer, I open one dashboard to see which screens and actions people use,
  where they drop off, how often errors happen per session, and how groups are actually
  used, so I can prioritise the roadmap on evidence.
- As any user, I trust that error reports never contain my name, my friends' names or our
  amounts, and that deleting my account removes who I am from the warehouse.

## Acceptance criteria

### Error reports

- **AC1** Given error reports are on, when an uncaught error happens anywhere in the app,
  then a report is sent with: report ID, time, platform (Android / web / iOS), OS or
  browser name and version, app version, app language, signed-in yes/no, online
  yes/no, a random session ID (not linked to the account), the error type, message and
  stack trace, and the last 30 breadcrumbs.
- **AC2** Given error reports are on, when the app shows the user an error message
  (a failed sign-in, a failed sync, a failed save), then a report is sent for that
  failure as in AC1.
- **AC3** Breadcrumbs record each screen opened (as its route pattern, e.g.
  `/groups/:id`, never with real IDs) and each user action by name (e.g. `createGroup`,
  `signIn`, `saveExpense`) with the time, in order.
- **AC4** An error report never contains the account uid or email, a group, member or
  document ID, a group or member name, an expense description, an amount, or an invite
  token — including inside error messages and stack traces. A test feeds such values
  through an error and checks the sent report holds none of them.
- **AC5** Given the user is not signed in, when an error happens on the sign-in screen
  (including a sign-in reported as failed, and a sign-in blocked by an in-app browser),
  then the report is sent as in AC1.

### Consent and usage analytics

- **AC6** The sign-in screen shows one line under the sign-in buttons, "By continuing,
  you agree to the Privacy Policy", with "Privacy Policy" linking to it. The details of
  what is tracked are in the policy only, not on the screen.
- **AC7** When a person signs in for the first time, then the account is created with the
  agreement time and the privacy policy version, and the app opens as usual. Nothing
  else is asked, on this or any other device.
- **AC8** Given the user is signed in (and so has agreed), every action they take is sent
  as an event: each screen opened; each tap on a button, menu item, tab, switch, chip or
  list item; each form submitted or abandoned; each dialog or sheet opened and closed;
  each pull-to-refresh, swipe and share; and each operation it triggers (save, delete,
  join, sync, sign-in, …) with its result (success, or the failure type) and duration.
  Every event carries: uid, session ID, time, event name, screen route pattern, platform,
  app version, app language and online yes/no. Events never contain names, descriptions,
  amounts, document IDs or invite tokens.
- **AC8a** No interactive element can be added to the app without an event name: a test
  fails the build if a tappable widget or an operation has none.
- **AC9** Before sign-in, no usage event is recorded or sent; only error reports,
  governed by their own switch.
- **AC10** When any user creates or changes a group, member, expense, settlement or
  activity entry, then that record appears in the warehouse within 24 hours.
- **AC11** Given an account is deleted, then within 24 hours its row in `dim_user`,
  including its history, is gone from every warehouse table, and no table holds a name or
  email of that user. BigQuery may keep the earlier table versions for up to 2 more days
  for recovery (time travel), then 7 days that only Google can restore (fail-safe); the
  privacy policy says so. Its usage events and copied records stay, keyed only by the
  uid.
- **AC12** When the release that ships R-4 rolls out, every account created before it is
  deleted with its cloud data (including the groups only they belonged to). On the first
  launch of the new version, the app shows sign-in. The release
  notes and the site say so in EN and VI before the release.

### Delivery and limits

- **AC13** Given the device is offline, when an error report or usage event is recorded,
  then it waits on the device and is sent once the device is online, even after an app
  restart. At most 50 error reports and 2,000 usage events wait; the oldest are dropped
  first.
- **AC14** Usage events are sent in batches: at most one request per minute while the
  app is open, plus one when it goes to the background.
- **AC15** The same error (same type and stack) is sent at most once per app session, with
  a count of how many times it happened.
- **AC16** One install sends at most 50 error reports and 5,000 usage events per day; the
  rest are dropped.
- **AC17** Sending never blocks, slows or interrupts the user, and a failure to send is
  never shown to the user.

### Storage, access and alerts

- **AC18** Reports and events are kept in BigQuery indefinitely. Only the maintainer can
  read them; no client can read, change or delete anything once sent.
- **AC19** Every error report is also a Cloud Logging entry with severity ERROR, carrying
  the report ID, platform and app version. A log-based alert emails the maintainer when
  error reports arrive, rate-limited so that a burst sends one email, not hundreds. Given
  a report ID, the maintainer finds its reports in Logs Explorer (last 30 days) and in
  BigQuery (any time).

### Zero cost

- **AC20** The endpoint rejects, without writing anything, any request without a valid
  App Check token, any usage event batch without a valid Firebase ID token whose uid
  matches the events, any body over 64 KB, and any payload that does not match the
  report or event schema.
- **AC21** The endpoint scales to zero when idle and never runs more than one instance.
- **AC22** Writes to BigQuery use only free paths (the Storage Write API within its
  monthly free tier, or batch loads), never billed streaming inserts. Cloud Logging uses
  only the default bucket and its default 30-day retention.
- **AC23** The endpoint's project is covered by the existing budget and kill switch, and an
  alert emails the maintainer when the warehouse's storage passes 80 % of the BigQuery
  free tier.
- **AC24** At ~100 active users, a month of billing shows $0 for Cloud Run, Cloud Logging,
  Cloud Monitoring and BigQuery.

### Diagnostics screen

- **AC25** The Settings app bar has a wrench icon (screen reader label "Diagnostics")
  that opens a Diagnostics screen; the main Settings list shows nothing about error
  reports. The Diagnostics screen has a switch "Send anonymous error reports" (on by
  default) with a one-line explanation and a link to the privacy policy, and shows the
  app version and build, the platform, and how many error reports are waiting to be
  sent.
- **AC26** When the user turns the error report switch off, nothing more is recorded or
  sent, and reports still waiting on the device are deleted. Turning it back on starts
  recording again with a new report ID.
- **AC27** The Diagnostics screen shows the report ID (short, easy to read aloud, e.g. `7KQ-4MZ`) while
  error reports are on; tapping it copies it and confirms with "Copied".
- **AC28** The error report choice and the report ID survive app restarts, sign-out and
  sign-in.
  Deleting the account does not delete error reports already sent (they are not linked to
  it), and the privacy policy says so.

### Copy and docs

- **AC29** All new text exists in EN and VI.
- **AC30** The privacy policy, the Play Data safety form, the store listing and the site
  no longer claim "no analytics" or "no crash reporting". They describe error reports
  (anonymous, on by default, kept indefinitely, can be turned off; Diagnostics and the
  report ID as a device ID), usage analytics (required to use the app, linked to the
  account, kept indefinitely; App interactions), the copy of group data and the user's
  name and email for analytics, and what deleting the account removes and keeps
  (including the 2-day time travel and 7-day fail-safe copies).

### Dashboard

- **AC31** A dashboard built with Evidence from the dbt models shows, refreshed daily after
  the pipeline runs: daily, weekly and monthly active users; sessions and session length;
  the most used screens and actions; the funnel first sign-in → agreed → first group →
  first expense → first invite accepted; errors per 100 sessions by platform and app
  version, and the top error types; operation failure rate and median duration by
  operation; groups, expenses and settlements created per week.
- **AC32** Only the maintainer can open the dashboard (sign-in required). The public
  data-platform repository holds its page and query definitions but no data or query
  results, and building and hosting it costs nothing.

## Edge cases checklist

- Offline / cold start / sync: reports and events recorded offline are queued (AC13); an
  error during app start, before Settings are loaded, is still reported if error reports
  are on, and dropped if they were turned off. Records edited offline are copied once
  they sync.
- ~~Group shape~~: not applicable — every account has agreed, so whole groups are copied.
- Localisation: switch labels, explanations and the sign-in line fit at default font
  size in VI.
- Empty / error states: sending is silent (AC17). If storing the agreement fails at
  first sign-in, the sign-in fails like any other failed sign-in and can be retried.
- Accessibility: switches and the policy link have screen reader labels; the report ID is
  read out character by character and is selectable.
- ~~Money~~: not applicable — reports and events carry no amounts (AC4, AC8); copied
  group records are copied as they are.

## Success check

- The three known tester bugs (sign-in reported as failed, sign-in in in-app browsers,
  no navigation after creating a group) each produce a report that shows the error and
  the steps before it, and an alert email, verified by reproducing them once on web and
  Android after R-4 ships.
- Given a tester's report ID, the maintainer finds their reports in under 5 minutes.
- A month after release, the dashboard answers "errors per 100 sessions by platform",
  "where do new users drop off before their first expense" and "share of active users who
  log an expense each week" without writing a query.
- Supports the crash-free users bar (≥ 99.5 %) and "one shared truth" by making sync and
  sign-in failures visible, and "free to run at small scale" (AC24).

## Out of scope

- Any third-party SDK.
- Paging, or alerts other than log-based emails.
- Dashboards other than the one in AC31, and sharing it with anyone but the maintainer.
- A screen to view or share the local log by hand.
- Fixing the three known bugs — each is tracked as its own bug report.
- Migrating existing accounts' data instead of deleting it (AC12).

## Open questions

- A user who never gets past sign-in cannot reach Settings, so cannot turn error reports
  off before their first sign-in errors are sent. Accepted for now and stated in the
  privacy policy; revisit if a tester objects.
- Requiring usage tracking to use the app means consent is not freely given in the
  GDPR or Vietnam Decree 13 sense, and Google Play review may ask for it to be optional.
  Accepted for now: the privacy policy states it as a condition of the service, not as
  optional consent. Revisit if Play review or a user objects.
- Cloud Monitoring has announced charges for alerting policies; confirm the alerts in
  AC19 and AC23 stay at $0 before shipping, or cut them to what the free tier allows.
- Keeping everything indefinitely relies on the BigQuery free storage tier; the storage
  alert (AC23) is the trigger to revisit retention.
