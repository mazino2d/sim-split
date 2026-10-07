# R-4 Anonymous error reports

Status: ready   ·   Serves: UC-7, all UCs   ·   Roadmap: Now

## Problem

Friends testing the web and Android builds hit small bugs and describe them afterwards in
chat: sign-in says it failed although it worked, sign-in does not work inside some apps'
in-app browsers, and creating a group does not open it. From a description alone the
maintainer cannot tell what happened, on which platform or in what order, so the bugs
stay unfixed and trust in the app erodes.

The app should record what went wrong and the steps that led to it, and send that to the
maintainer without the tester having to do anything — while never revealing who the
tester is or what their groups contain.

## Decisions (2026-10-08)

| Topic | Decision |
| --- | --- |
| Collection | Automatic, on by default, with an off switch in Settings (opt-out). Acceptable only because reports are anonymous; linking reports to accounts would require opt-in. |
| Content | Errors plus breadcrumbs (the screens and actions before the error), platform and app version. Never the account, email, uid, group or member names, expense descriptions or amounts. |
| Destination | The app's own Firestore project. No third-party SDK (Crashlytics was ruled out: no web support, and it is a crash reporting service). |
| Retention | Reports are deleted automatically 30 days after they are received. |
| Before sign-in | Errors on the sign-in screen are reported too, without an account. |
| Report ID | Each install has a random report ID, shown in Settings, that a tester can quote to the maintainer. It is not linked to the account. |
| Notice | Settings and the privacy policy only — no banner, dialog or extra line on the sign-in screen (Calm). |
| Turning off | Stops recording and sending, and deletes reports still waiting on the device. |

## User stories

- As a tester who hit a bug, I tell the maintainer my report ID and what I was doing, so
  they can see exactly what went wrong without asking me to reproduce it.
- As the maintainer, I open the reports for a report ID, platform or app version and see
  the error with the screens and actions that led to it.
- As any user, I can turn error reports off in Settings, and I trust that reports never
  contain my name, my friends' names or our amounts.

## Acceptance criteria

### What is reported

- **AC1** Given error reports are on, when an uncaught error happens anywhere in the app,
  then a report is sent with: report ID, time, platform (Android / web / iOS), OS or
  browser name and version, app version, app language, signed-in yes/no, online
  yes/no, the error type, message and stack trace, and the last 30 breadcrumbs.
- **AC2** Given error reports are on, when the app shows the user an error message
  (a failed sign-in, a failed sync, a failed save), then a report is sent for that
  failure as in AC1.
- **AC3** Breadcrumbs record each screen opened (as its route pattern, e.g.
  `/groups/:id`, never with real IDs) and each user action by name (e.g. `createGroup`,
  `signIn`, `saveExpense`) with the time, in order.
- **AC4** A report never contains the account uid or email, a group, member or document
  ID, a group or member name, an expense description, an amount, or an invite token —
  including inside error messages and stack traces. A test feeds such values through an
  error and checks the sent report holds none of them.
- **AC5** Given the user is not signed in, when an error happens on the sign-in screen
  (including a sign-in reported as failed, and a sign-in blocked by an in-app browser),
  then the report is sent as in AC1.

### Delivery and limits

- **AC6** Given the device is offline, when an error happens, then the report waits on
  the device and is sent once the device is online, even after an app restart. At most
  50 reports wait; older ones are dropped first.
- **AC7** The same error (same type and stack) is sent at most once per app session, with
  a count of how many times it happened.
- **AC8** One install sends at most 50 reports per day; the rest are dropped.
- **AC9** Sending a report never blocks, slows or interrupts the user, and a failure to
  send is never shown to the user.
- **AC10** Nobody can read, change or delete reports from the app; only the maintainer
  can read them, from the Firebase console. A report is deleted automatically 30 days
  after it is received.

### Settings

- **AC11** Settings has a switch "Send anonymous error reports" (on by default) with a
  one-line explanation and a link to the privacy policy.
- **AC12** When the user turns the switch off, nothing more is recorded or sent, and
  reports still waiting on the device are deleted. Turning it back on starts recording
  again with a new report ID.
- **AC13** Settings shows the report ID (short, easy to read aloud, e.g. `7KQ-4MZ`) while
  reports are on; tapping it copies it and confirms with "Copied".
- **AC14** The choice and the report ID survive app restarts, sign-out and sign-in.
  Deleting the account does not delete reports already sent (they are not linked to it),
  and the privacy policy says so.

### Copy and docs

- **AC15** All new text exists in EN and VI.
- **AC16** The privacy policy, the Play Data safety form (Diagnostics), the store listing
  and the site no longer claim "no crash reporting"; they describe what reports contain,
  that they are anonymous, kept 30 days and can be turned off.

## Edge cases checklist

- Offline / cold start / sync: errors while offline are queued (AC6); an error during
  app start, before Settings are loaded, is still reported if reports are on, and
  dropped if they were turned off.
- Localisation: the switch label and explanation fit on one line plus one wrapped line
  in VI at default font size.
- Empty / error states: no user-visible state — sending is silent (AC9).
- Accessibility: the switch has a screen reader label; the report ID is read out
  character by character and is selectable.
- ~~Money~~ and ~~Group shape~~: not applicable — reports carry no amounts or group data
  (AC4).

## Success check

- The three known tester bugs (sign-in reported as failed, sign-in in in-app browsers,
  no navigation after creating a group) each produce a report that shows the error and
  the steps before it, verified by reproducing them once on web and Android after R-4
  ships.
- Given a tester's report ID, the maintainer finds their reports in under 5 minutes.
- Supports the crash-free users bar (≥ 99.5 %) and "one shared truth" by making sync and
  sign-in failures visible.
- The backend stays within the free tier at ~100 users (AC7, AC8, AC10).

## Out of scope

- Usage analytics: screen views, funnels or counts sent when nothing went wrong.
- Any third-party SDK, including Crashlytics.
- A screen to view or share the local log by hand.
- Alerts or dashboards for the maintainer beyond the Firebase console.
- Fixing the three known bugs — each is tracked as its own bug report.

## Open questions

- A user who never gets past sign-in cannot reach Settings, so cannot turn reports off
  before their first sign-in errors are sent. Accepted for now and stated in the privacy
  policy; revisit if a tester objects.
- With notice in Settings and the privacy policy only, most users will not know reports
  exist. Revisit (one line on the sign-in screen) if the opt-out is ever questioned.
