# R-3 Co-worked groups

Status: ready   ·   Serves: UC-1, UC-2, UC-3, UC-4, UC-7, UC-8, UC-9   ·   Roadmap: Now

## Problem

On a trip, only the bookkeeper can see the numbers. Friends keep asking "how much do I
owe?", and the bookkeeper has to screenshot balances or read them out. When a friend pays
for something while the bookkeeper is away, the expense is forgotten or logged twice.
Each member should be able to open the same group on their own phone, see the live
balances, and add what they paid, without making the bookkeeper's flow any slower.

The group is friends who trust each other, so everyone has full rights and there are no
roles or approvals. Because anyone can change anything, every change must be auditable:
when a number looks wrong, anyone can see who changed what and when.

## Decisions (2026-10-03)

| Topic | Decision |
| --- | --- |
| Sign-in | Required to use the app. Google and Apple only, one tap, no passwords, no anonymous accounts. |
| Persona | The bookkeeper stays primary. Co-members can view and add expenses. |
| Permissions | Every member of a group can create, edit and delete anything in the group (trust-based, like Tricount). |
| Audit | Every change is recorded in an append-only activity history (who, when, old → new values) that every member can read and nobody can edit or delete. |
| Offline | A network is needed only for first sign-in and for joining a group. After that, all core flows (log, edit, balances, settle) work fully offline and sync when back online. |
| Architecture | Drift stays the local source of truth that the UI reads from. Local writes go to an outbox that pushes to Firestore, and remote changes are pulled into Drift. The domain layer is unchanged. |
| Existing local data | Uploaded to the user's account automatically on first sign-in. |
| Platforms | Android, web and iOS. Web gets every feature Android has, built right after cloud push, because it is the fastest platform to test end to end. If the Apple Developer account is not active in time, Android and web (Google sign-in only) ship first and iOS follows. |
| Backend | Firebase Auth (Identity Platform) + Cloud Firestore in a dedicated project, `simsplit-as-se1-prd`, managed as code in `mazino2d/everything-as-code`. It runs on the Blaze plan because Identity Platform needs billing, but the target cost is zero: usage stays within the free quotas, a budget sends alerts, and a kill switch unlinks billing once actual cost reaches the budget. |

## User stories

- As the trip bookkeeper, I sign in once with Google or Apple so my groups are saved to my
  account and kept on any phone I use.
- As the trip bookkeeper, I share an invite link in our chat so my friends can open the
  group on their own phones.
- As a co-member, I open the invite link, sign in, pick which member I am, and see the
  same balances as everyone else.
- As a co-member, I add an expense I paid, and the bookkeeper sees it without asking me.
- As any member, I can see who added or last edited an expense, so I trust the numbers.
- As a user, I can sign out or delete my account and its cloud data from Settings.

## Acceptance criteria

### Sign-in (UC-7)

- **AC1** Given a fresh install, when the app opens, then a single sign-in screen shows
  "Continue with Google" and "Continue with Apple" and nothing else. There is no
  onboarding carousel and no profile form.
- **AC1b** Given Android, iOS or web, when the user signs in with either provider, then they
  reach the same account and the same groups on every platform.
- **AC2** Given the sign-in screen, when the user completes Google or Apple sign-in, then
  they land on the group list in ≤ 2 taps from launch (excluding the provider's own
  screens).
- **AC3** Given no network on the sign-in screen, when the user taps a provider, then a
  one-line message says a connection is needed to sign in, and the screen stays usable
  once the network returns.
- **AC4** Given a signed-in user, when they relaunch the app with no network, then they are
  not signed out and their groups are visible from the local cache.
- **AC5** Given Settings, when the user taps Sign out, then they return to the sign-in
  screen and no group data from that account stays readable on the device.
- **AC6** Given Settings, when the user confirms Delete account, then their account is
  deleted, they are removed from every group, and groups where they were the only member
  are deleted from the cloud. Groups that still have other members are kept, and the
  deleted user's past expenses stay attributed to their member name.

### Migrating existing data

- **AC7** Given a v1.0 user with local groups, when they sign in for the first time, then
  every local group, member, expense, split and settlement is uploaded to their account
  with identical IDs and amounts, and they are linked as the group's owner and as the
  member they choose (asked once per group with more than one member; skipped for groups
  with one member).
- **AC8** Given a migration is interrupted (app killed, network lost), when the app
  reopens online, then the migration resumes and finishes without duplicates or lost
  records.

### Sharing a group (UC-8)

- **AC9** Given a group, when any member taps Share group, then the system share sheet
  opens with an invite link and a one-line message in the user's language.
- **AC10** Given a signed-in friend opens the invite link, when the app opens, then it
  shows the group name and the list of unclaimed member names plus "I'm not on the list".
  Picking one joins the group as that member in ≤ 2 taps.
- **AC11** Given "I'm not on the list", when the friend enters a name, then a new member is
  added, and existing expenses and balances are unchanged.
- **AC12** Given a friend who is not signed in opens the invite link, when they finish
  sign-in, then they continue straight to the join screen for that group.
- **AC13** Given a group owner, when they tap Reset invite link, then old links stop
  working and current members keep their access.
- **AC14** Given a member, when they tap Leave group, then they lose access. Their member
  name and all expenses stay in the group, and their name becomes unclaimed again.

### Sync and collaboration (UC-1, UC-2, UC-4)

- **AC15** Given two members online in the same group, when one saves, edits or deletes an
  expense or settlement, then the change appears on the other device within 5 s without a
  manual refresh, and balances update.
- **AC16** Given a signed-in member with no network (including right after a cold start),
  when they create, edit or delete an expense or settlement, then it applies immediately
  locally with a subtle "not synced yet" mark, balances update, and the change uploads once
  online without any user action, even after the app was killed in between.
- **AC17** Given two members edit the same expense at the same time, when both sync, then
  the last write wins for the whole expense (amount, payer, splits together, never a
  mix), and both devices end with the same version.
- **AC18** Given any expense, when a member opens it, then they see "Added by <name>" and,
  if edited, "Edited by <name> · <relative time>".
- **AC18b** Given a member who was offline for days, when they come back online, then the
  outbox drains in order and remote changes made meanwhile are pulled in. Every device then
  converges to the same data, and no local change is lost unless it was overwritten by a
  later edit of the same record (AC17).
- **AC19** Given a deleted expense, when another member opens the group, then it is gone
  and balances exclude it on every device.
- **AC20** Given the core loop, when the bookkeeper logs an equal-split expense in a shared
  group, online or offline, then UC-1.1 still holds (≤ 10 s, ≤ 4 taps). Sync never blocks
  the Save button.

### Audit (UC-9)

- **AC25** Given a group, when a member opens Activity from the group screen (≤ 2 taps),
  then they see a newest-first list of every change: "<member> added / edited / deleted
  <item> · <time>".
- **AC26** Given an edit entry in the activity history, when it is opened, then it shows
  each changed field with old → new values, including amount, payer and per-member shares.
- **AC27** Given a deleted expense or settlement, when its activity entry is opened, then
  its full details at deletion time are shown.
- **AC28** Given any member, when they try to edit or delete an activity entry (in the app
  or directly against the backend), then it is impossible: the UI offers no such action,
  and security rules reject the write.
- **AC29** Given a change made offline, when it syncs, then its activity entry is written
  in the same atomic write as the change itself and shows the device time of the change.
  A change can never sync without its activity entry.
- **AC30** Given changes to members (added, renamed, claimed, left) and group settings
  (name, currency), when they happen, then they also appear in the activity history.

### Trust in numbers

- **AC21** Given any expense synced between devices, when it is read back, then
  `amountCents` and every split's `amountCents` are identical to what was saved, and the
  splits sum exactly to the total.
- **AC22** Given any sequence of concurrent edits in a group, when all devices are synced,
  then every device shows the same balances, to the smallest currency unit.
- **AC23** Given a member who is not in a group, when they try to read or write that group
  through the backend directly, then security rules reject the request.

### Cost

- **AC24** Given a load test that simulates 100 users × 5 app opens/day in groups of 6 with
  200 expenses each, when the daily Firestore usage is measured, then reads, writes and
  storage stay below the free quotas with ≥ 2× headroom.

## Edge cases checklist

- Offline / cold start: a cold start with no network after sign-in shows the local
  groups (AC4). A first sign-in or join with no network fails calmly (AC3). Changes made
  offline sync later in order (AC16, AC18b). Deleting a record while offline is kept as a
  tombstone so the deletion syncs.
- Money: amounts are stored as integer cents in the cloud, never as floats. VND has no
  decimals. Splits are written atomically with their expense (AC17, AC21).
- Group shape: a 1-member group can be shared. A member who leaves keeps their history
  (AC14). An account that has been deleted shows as its member name. Two users must not
  claim the same member: the second user sees the name as taken.
- Localisation: all new copy (sign-in, invite message, join screen, sync mark, account
  deletion) exists in EN and VI. The invite message is written natively in Vietnamese.
- Empty / error states: an invalid or reset invite link says "This invite link no longer
  works — ask a member for a new one". A failed sync retries silently; after 24 h unsynced,
  one inline line appears on the group.
- Accessibility: the provider buttons follow Google and Apple branding rules, scale with
  font size, and have screen-reader labels. The sync mark has a text alternative.

## Success check

- UC-1.1 still holds in a shared group: a timed run on a mid-range Android phone, recorded
  in the PR.
- AC15 is verified with two real devices on the same group.
- The cost load test (AC24) is recorded in the PR before release.
- Crash-free users stay ≥ 99.5 % after release (Play vitals).

## Out of scope

- Email/password, phone OTP and anonymous sign-in.
- Push notifications for new expenses. These would need a separate triage against the Calm
  principle.
- Roles and permissions beyond "member" and "owner" (the owner can only reset the invite
  link).
- Per-field merging of conflicting edits.
- Comments, receipts, photos, chat.

## Follow-ups this spec requires

- The web app gets sign-in and sync like Android (plan phase P4). It also gives the web
  account-deletion path below.
- Rewrite the Play Store listing (EN + VI): it currently promises "completely offline" and
  "No account needed".
- Update the Play Data safety form: account info (email, name) and user content are now
  collected and stored in the cloud. Publish a privacy policy page.
- Add an in-app and web account-deletion path (a Play policy requirement for apps with
  accounts).
- iOS release: Apple Developer Program membership (99 USD/year — not a backend cost, but
  the only paid item), App Store Connect listing in EN + VI, App Privacy labels matching
  the Data safety form, and Universal Links for invite links (Android: App Links).
- Configure Sign in with Apple (required by App Store guideline 4.8 alongside Google
  sign-in) and in-app account deletion (guideline 5.1.1(v)).
- When R-3 ships, remove the *(R-3)* markers in `docs/product/use-cases.md` and add
  end-to-end coverage for the new criteria to the `e2e-tester` suite.

## Open questions

Decided on 2026-10-03: for conflict ordering, the last write to reach the server wins
(`updatedAt` is a server timestamp), so device clocks do not matter. See the
[implementation plan](../../implementations/R-3-online-shared-groups.md).

- Should a deleted expense or settlement be restorable from the activity history (one tap
  "Restore", itself logged), or only viewable?
- Should the bookkeeper be able to remove another member's access? The current answer is
  no (only leave and reset link) to keep things simple.
