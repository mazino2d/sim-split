# R-9 Notifications and CRM as code

Status: draft (P8 settings added 2026-11-22)   ·   Serves: UC-4, UC-9, all UCs   ·   Roadmap: Next

## Problem

A shared group only works if everyone sees what the others log. Today a member finds out
that a friend added the dinner bill only by opening the app, so mistakes stay unnoticed
until settling, and debts sit for weeks because nobody is reminded. The maintainer also
has no way to tell users about something that matters to them (a new version that fixes
their bug, a privacy policy change) other than the store listing.

SimSplit should tell members what changed in their groups, remind people who asked for it
that they still owe money, and let the maintainer send rare, useful notices — without
breaking the first principle: the app never interrupts with something the user did not
ask for. Every message, the rules for who gets it and the limits that keep it calm are
code in the repo, reviewed in a pull request like the rest of the app.

## Decisions (2026-11-21)

| Topic | Decision |
| --- | --- |
| Goals | Three, in order: group activity, settle reminders, notices from the maintainer (new versions, policy changes, nudges tied to the user's own data). Re-engagement is allowed only as an opt-in notice about the user's own groups, never "we miss you". |
| Channels | Push (Android and the web app) and in-app banners. Email later, for account and policy messages only. No SMS: sign-in gives no phone number, and SMS costs money per message. iOS waits for R-3 P8. |
| Categories | **Group activity:** on once the user allows notifications, mutable per group. **Settle reminders:** off until the user turns them on. **Updates:** off until the user turns them on. In-app banners are not a category: they never interrupt and can be dismissed. |
| Asking | The app asks for notification permission once, when the user first has a group with another member, with one line saying what they will get. Never on launch, never again after a refusal; Settings explains how to turn it on. Allowing it is the user asking for group activity (principle 1). |
| Calm limits | Quiet hours 21:00–08:00 on the device's clock: a message due then waits until 08:00. Group activity is batched (several changes in a group become one message). Settle reminders and updates together: at most one message per user per week. These limits apply to every message and no single message can override them. |
| Operated as code | Categories, the limits, group activity rules, schedules, one-off campaigns, audiences and message templates (EN + VI) are files in the repo. A pull request shows what will change and a preview of every message; merging applies it to dev; production follows the maintainer's approval. No admin web page. |
| Audiences | Chosen by rules over user traits (platform, language, activity, groups, what they owe, what they turned on), written as config, not SQL. The traits are computed daily in the warehouse. Free-form queries and event sequences are out of scope. |
| Content | Push messages name the group, the member and, for expenses, the title and amount, so they are useful on a lock screen. They pass through Firebase Cloud Messaging (Google), the same processor that already stores the groups; the privacy policy says so. |
| Cost | Zero, like R-4: free tiers and hard limits, no paid sending service. |

## User stories

- As a group member, I get one notification when friends add or settle expenses in my
  group, so I can catch a wrong amount the same day.
- As a member who is muting a busy group, I keep its activity out of my notifications
  without leaving the group.
- As someone who forgets to pay back, I can turn on a weekly reminder that tells me who I
  still owe and how much.
- As any user, I am never woken up, spammed or nagged: nothing at night, nothing I did not
  allow, and one switch per kind of message.
- As the maintainer, I write a notice or change a rule in a pull request, see exactly who
  would get what in which language, and ship it with a comment on the PR once I am happy.

## Acceptance criteria

### Permission and settings

- **AC1** Given a signed-in user who has never been asked, when they first open a group
  that has another member, then the group shows an inline, dismissible line (not a
  dialog) explaining group activity notifications, with Turn on, which shows the system
  permission prompt, and Not now. Whatever the answer, the line never shows again on
  that device; it is never shown on launch or before sign-in.
- **AC2** Given the user refused the permission, then the app never asks again on its own;
  Settings → Notifications says notifications are off and how to turn them on in the
  system settings.
- **AC3** Settings → Notifications has one switch per category (Group activity, Settle
  reminders, Updates) with a one-line description each. Defaults: Group activity on,
  Settle reminders off, Updates off. Changes apply to every device of the account within
  one minute of syncing.
- **AC4** Given a group, when the user chooses Mute notifications in the group's menu, then
  they get no group activity for that group on any device until they unmute it; the group
  shows that it is muted.
- **AC5** On Android, each category is its own notification channel with the same name, so
  the system settings show the same choices.

### Group activity

- **AC6** Given members A and B of a group with group activity on, when A adds, edits or
  deletes an expense or records a settlement, then B's devices get a notification naming
  the group, A, and for an expense its title and amount in the group currency; A gets
  none for their own change.
- **AC7** Given several changes in the same group within 10 minutes, then each recipient
  gets one notification that counts them ("3 new expenses") instead of one per change.
- **AC8** Tapping a group activity notification opens that group (one change: that
  expense or settlement) in the app, after sign-in if needed.
- **AC9** No notification goes to a removed member, a member who left, a signed-out device,
  or about an archived group.
- **AC10** Amounts in a notification equal the amounts the app shows for the same record,
  to the smallest currency unit, formatted the same way.

### Settle reminders and updates

- **AC11** Given settle reminders on and money owed in an open group for more than 14 days,
  then the user gets at most one reminder per week, on Sunday at 19:00 device time, naming
  the total owed and how many people it is owed to; tapping it opens the settle screen of
  the group with the largest debt.
- **AC12** Given a campaign with an in-app banner, then signed-in users in its audience see
  one banner at the top of the home screen until they dismiss it or it expires; at most
  one banner shows at a time.
- **AC13** Updates and settle reminders together never exceed one push per user per week,
  whatever campaigns are configured.

### Calm limits

- **AC14** No push is shown between 21:00 and 08:00 device time; a message due then is
  delivered at 08:00, or dropped if it is out of date by then (a batched activity message
  is kept; a campaign past its end is dropped).
- **AC15** A kill switch in the config stops every send within the time it takes to apply
  the config, without an app release.

### Operated as code

- **AC16** A pull request that changes the notification config fails its checks when a
  template lacks EN or VI, uses an unknown variable, exceeds the push length, names an
  unknown trait or category, or breaks a calm limit.
- **AC17** The pull request shows, for every changed message, a rendered preview in EN and
  VI, and for every changed audience, its rules in plain words.
- **AC18** Merging applies the config to dev only; dev users (the SimSplit [Dev] build and
  the dev web app) get the messages first, and a campaign goes out on dev at the next
  tick after the merge. Production runs the exact build dev ran, only after the maintainer
  comments `crm apply` on the PR; there it follows each campaign's send time. Audiences
  are not counted before that.
- **AC19** A campaign is sent at most once to each device, even if a send is retried or the
  config is applied again.

### Audiences

- **AC20** An audience is a named set of rules (all of / any of, one level of nesting) over
  traits from a fixed catalog; each trait has a type (choice, number, days ago, yes/no,
  version) and only the operators for its type.
- **AC21** Traits are refreshed daily; a scheduled send whose traits are more than 36 hours
  old is skipped and the maintainer is alerted.
- **AC22** Whatever the audience says, a message goes only to users who have its category
  on and the device permission granted, checked at send time.

### Privacy, measurement and docs

- **AC23** Deleting the account removes its devices, so no further notification reaches
  them; signing out removes that device.
- **AC24** The maintainer can see per message and per campaign how many were sent and how
  many opened, in the warehouse dashboard.
- **AC25** The privacy policy, the Play Data safety form and the strategy say what is
  collected for notifications (device token, language, time zone, preferences) and that
  traits from usage data choose who gets a notice, before the first notification is sent
  on production.

### More control, same calm defaults (P8, 2026-11-22)

Notification settings grow from three switches to a few choices per kind. Every new
choice starts at today's behaviour, so nobody who never opens the screen notices a
change, and none of them can make notifications louder than the calm limits allow.

- **AC26** Group activity has a detail screen with one switch per kind of change:
  new expenses, edited expenses, deleted expenses, settlements (all on) and members
  joining (off). Only the kinds that are on are notified.
- **AC27** "Only changes that involve me" (off by default): when on, an expense
  change is notified only if the user's member paid it or has a share in it, and a
  settlement only if it is from or to that member.
- **AC28** Bundling: "Every 10 minutes" (default), "Every 30 minutes", "Every hour"
  or "Once a day at 19:00". A longer choice never delays a message less than the
  default does; the daily summary counts the day's changes per group.
- **AC29** Per group, from the group menu and from Settings → Notifications →
  Groups: "All activity" (default), "Only changes that involve me", "Off", or
  "Off until tomorrow 08:00". This replaces Mute / Unmute; groups muted before keep
  "Off".
- **AC30** Pause all notifications: "1 hour", "Until tomorrow 08:00" or "1 week".
  While paused, nothing is pushed and nothing is kept for later, except group
  activity, which arrives as one summary when the pause ends. Settings shows when
  the pause ends and a Resume button.
- **AC31** Quiet hours can be made longer (start earlier than 21:00, end later than
  08:00) but never shorter; the screen only offers longer ranges.
- **AC32** Settle reminders, when on, let the user pick the day of the week
  (default Sunday), the time (default 19:00, between 08:00 and 21:00) and how old a
  debt must be (7, 14 (default) or 30 days). Still at most one per week, sharing the
  weekly cap with updates (AC13).
- **AC33** "Send a test notification", on the Diagnostics screen (with the other debug
  tools, not in Settings → Notifications), sends one push to this device within a
  minute, outside the weekly cap and quiet hours, at most once every 10 minutes.
- **AC34** All choices sync to every device of the account and are read by the
  sender at send time, like the switches today (AC3, AC22).
- **AC35** Every new string exists in EN and VI, and the screens follow the design
  system: one level of detail per kind, no dialogs except the time picker.



- Offline / sync: a preference changed offline applies once synced; a notification about a
  record the device has not synced yet opens the group and shows the record once synced.
  Two devices of the same user both get the notification.
- Money: amounts formatted per group currency (VND without decimals); a reminder total
  across groups in different currencies lists the largest one and "and N more" instead of
  adding currencies.
- Group shape: a group with one member never triggers activity; a member removed while a
  batched message is pending does not get it.
- Localisation: each device gets its own app language; Vietnamese copy written natively;
  long group names are cut in the title, never the amount.
- Empty / error states: notifications off in the system shows a calm line in Settings with
  the way to turn them on; no banner or dialog about it.
- Accessibility: notifications use the system's own rendering; banners scale with the font
  size and have screen reader labels.

## Success check

- UC-9: a change by one member reaches the others within 15 minutes (10-minute batch plus
  delivery) outside quiet hours, checked on dev with two accounts.
- UC-4: the share of groups with debts older than 14 days drops among users who turn on
  settle reminders, compared with those who do not (warehouse, 8 weeks after shipping).
- Calm: fewer than 5 % of users who allowed notifications turn group activity off in the
  first month; zero pushes logged inside quiet hours.

## Out of scope

- SMS, iOS push (until R-3 P8), marketing email.
- An admin web page; free-form SQL or event-sequence audiences; real-time traits.
- A notification inbox inside the app.
- Notifications for invitations, comments or mentions (no such features yet).

## Open questions

- Email in the last phase: which sender (Amazon SES, Resend or Brevo free tier) and from
  which domain. Decide before that phase starts.
