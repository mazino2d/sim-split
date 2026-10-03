# Use cases and success criteria

Core use cases carry measurable success criteria; a change that regresses one is a bug.
Supporting use cases must work correctly but are optimised only when it costs the core
nothing.

Criteria marked *(R-3)* belong to online shared groups
([spec](specs/R-3-online-shared-groups.md)) and are not built yet. Until R-3 ships, the
app is local-only and those criteria do not apply.

"Offline" below means signed in, with no network. "Every device" means every signed-in
member of that group, on Android or iOS.

## Core

### UC-1 Log an expense

> As the trip bookkeeper — or any co-member — I record what someone just paid so I can
> stop thinking about it.

| # | Success criterion |
| --- | --- |
| 1.1 | Equal split among all members: ≤ 10 s and ≤ 4 taps from the group screen to saved, online or offline. Sync never blocks Save. |
| 1.2 | Works offline, including right after a cold start. The entry syncs to every device once online, within 5 s when both devices are online. *(R-3 for sync)* |
| 1.3 | Defaults (payer, split, currency, date) are correct without touching them in the common case. In a shared group, the payer defaults to the last payer chosen on this device. |
| 1.4 | Saved amounts and per-member shares always sum exactly to the total, on every device after sync. |
| 1.5 | Any member can edit or delete any entry in ≤ 3 taps from the expense list. |
| 1.6 | Each entry shows who added it and, if edited, who last edited it and when. *(R-3)* |
| 1.7 | Concurrent edits of the same entry resolve to one whole version (last write wins). Fields are never mixed, and an entry is lost only if it was deleted. *(R-3)* |

### UC-2 See who owes whom

> As anyone in the group, on my own phone, I want to know what I owe or am owed, and why.

| # | Success criterion |
| --- | --- |
| 2.1 | Balances are reachable in 1 tap from the group screen. |
| 2.2 | Debts are simplified to the minimum practical number of transfers. |
| 2.3 | Every balance can be explained: the user can see which expenses produced it. |
| 2.4 | Balances update immediately after any local change, and within 5 s of a change synced from another member. *(R-3 for remote changes)* |
| 2.5 | Amounts are formatted in the group currency and the user's locale. |
| 2.6 | Once synced, every device shows identical balances to the smallest currency unit. *(R-3)* |
| 2.7 | A signed-in member sees their own member highlighted ("You") in the balances. *(R-3)* |

## Supporting

### UC-3 Set up a group and its members

| # | Success criterion |
| --- | --- |
| 3.1 | A group can be created offline, with no contacts permission. |
| 3.2 | Members can be added mid-trip by any member, and existing balances are unchanged. |
| 3.3 | The group creator is linked to a member of the group (themselves) when the group is created. *(R-3)* |
| 3.4 | A member that is not linked to an account is a normal member: expenses can be logged for them by anyone. |

### UC-4 Record a settlement

| # | Success criterion |
| --- | --- |
| 4.1 | Any member can record a settlement, online or offline. Settled debts disappear from balances on every device after sync. |
| 4.2 | Settlement history is visible and shows who recorded each entry. *(R-3 for "who")* |
| 4.3 | Any member can edit or delete a settlement. Balances recompute exactly. |

### UC-5 Share the result with the group

| # | Success criterion |
| --- | --- |
| 5.1 | A plain-text or image summary of balances can be sent to any messaging app, for friends who do not install the app. *(Not built.)* |

### UC-6 Manage settings

| # | Success criterion |
| --- | --- |
| 6.1 | Language and theme changes apply without restart. |
| 6.2 | Settings shows the signed-in account (name and email) with Sign out and Delete account. *(R-3)* |

### UC-7 Sign in and manage the account *(R-3)*

| # | Success criterion |
| --- | --- |
| 7.1 | A fresh install shows one sign-in screen with only Google and Apple. The user reaches the group list in ≤ 2 taps, plus the provider's own screens. |
| 7.2 | The same account on Android and iOS shows the same groups. |
| 7.3 | The user is never signed out because of being offline. |
| 7.4 | On the first sign-in, all existing local data is uploaded unchanged, and an interrupted upload resumes without duplicates. |
| 7.5 | After Sign out, no group data from that account stays readable on the device. |
| 7.6 | Delete account works from inside the app (a Play and App Store requirement). It removes the user's account and access, and keeps their past expenses in shared groups under their member name. |

### UC-8 Invite friends to a shared group *(R-3)*

| # | Success criterion |
| --- | --- |
| 8.1 | Any member can share an invite link through the system share sheet. |
| 8.2 | A signed-in friend who opens the link joins in ≤ 2 taps by claiming an unclaimed member name or adding a new one. A friend who is not signed in continues to the join screen right after sign-in. |
| 8.3 | A member name can be claimed by only one account. |
| 8.4 | The owner can reset the link, and old links then stop working. A member can leave the group, and their member name and history stay. |
| 8.5 | Only members of a group can read or write it. This is enforced by backend security rules, not only by the UI. |

### UC-9 Review what changed in a group *(R-3)*

> As any member, when a number looks wrong, I want to see who changed what and when, so
> trust never turns into an argument.

| # | Success criterion |
| --- | --- |
| 9.1 | The group's activity history is reachable in ≤ 2 taps from the group screen. |
| 9.2 | Every create, edit and delete of an expense, settlement, member or group setting appears in it, with the member name, the time, and the changed values (old → new). |
| 9.3 | A deleted expense or settlement remains viewable in the history with its full details. |
| 9.4 | No member can edit or delete history entries. This is enforced by backend security rules. |
| 9.5 | Changes made offline appear in the history with the time they were made on the device, once synced. |
