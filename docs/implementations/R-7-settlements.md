# R-7 Settlements — implementation plan

Status: in progress (P1–P3 done)   ·   Spec: no spec document; the issues are the spec ([#116](https://github.com/mazino2d/sim-split/issues/116) settlement mode, [#117](https://github.com/mazino2d/sim-split/issues/117) archive, [#112](https://github.com/mazino2d/sim-split/issues/112) "My name")   ·   Written 2026-11-14

How the first part of R-7 gets built. The three issues share one Firestore rules
change, reviewed and deployed once. [#110](https://github.com/mazino2d/sim-split/issues/110)
(paid / share / net per member) and [#115](https://github.com/mazino2d/sim-split/issues/115)
(share image) build on #116 and get their own plan afterwards.

## Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Settlement mode fields | On `groups/{id}`: `settlementMode` (`"hub"` or `"simplified"`) and `settlementHubMemberId` (a member ID or null). Drift `groups` gets the same two columns (schema v6). Both go through `SyncCodec.group` and the puller like the other group fields | Shared by every member (#116), synced and audited like any group change. |
| Default mode | New groups are created with `hub`. A group without the field (every group created before R-7) reads as `simplified` | The decision for #116 is hub for new groups. Existing groups keep the suggestions their members already know, and can switch. |
| Default collector | `settlementHubMemberId` null means "the owner's member" (the member whose `linkedUid` is `ownerUid`). Removed or deleted collector → the owner's member. No owner's member (not synced yet, or the owner left without a member) → the balances screen shows the picker instead of suggestions | Stores nothing until someone picks a collector, so ownership changes (an owner leaving) move the default with them. |
| Hub algorithm | A pure function next to `CalculateDebts`: each member with a negative net pays the collector `|net|`; the collector pays each member with a positive net `net`. `CalculateDebts` takes the mode and collector and returns the same `DebtSummary` shape | Only suggestions change (#116); nets, balances and recorded settlements are untouched, and `SettleDebt` works unchanged in both modes. Sums stay exact in `int` cents. |
| Who archives | Only the owner archives and reopens (decision on #117). Enforced in a `SetGroupArchived` use case (`GroupFailure.notOwner`) and in the rules. A group created offline that has no `ownerUid` yet counts as owned by its creator | Same rule in the app and on the server, so another device can't bypass it. |
| Read-only while archived | Every use case that writes members, expenses or settlements, and `UpdateGroup` for anything but archiving, first checks the group and returns `GroupFailure.archived`. The rules reject creates and updates of `members`, `expenses` and `settlements` while the group is archived. Deletes stay allowed for the sole member, so deleting a group (or the account) still works | #117 asks for enforcement in the domain, not only hidden buttons. The rule stops an older build or another device from editing a closed group. |
| Joining an archived group | Refused: the `joining()` rule requires the group not to be archived, and the join screen shows "This group is archived" | Matches the suggestion in #117: nobody joins a closed trip. |
| "My name" | A new field `memberName` (string, 1–80 characters) on `users/{uid}`. The rules allow the account to update that one field and nothing else; consent stays immutable. The app caches it in `SharedPreferences` (`account_member_name`) so forms can prefill offline | #112: set once, follows the account to every device and the web. Firestore persistence is off, so the cache is what makes it work offline. |
| Prefill order | My name → the name last used on this device (`my_member_name`, as today) → Google `displayName` → empty. A prefilled value doesn't mark the form dirty | The order in #112. |
| Activity history | Group updates already record before/after. `activity_text.dart` gets labels for `settlementMode` and `settlementHubMemberId`, and archive and reopen get their own lines ("Khoi archived the group", "… reopened the group") instead of a field diff | UC-9: every change reads as a sentence. |
| Warehouse | No data-platform change is required: dlt adds `settlement_mode`, `settlement_hub_member_id` and `member_name` as new columns. A small data-platform PR adds the column hints afterwards | Schema evolution is on for the `simsplit_raw` resources. `member_name` sits next to `display_name` in `users`, which is replaced on every load, so a deleted account still leaves the warehouse. |

## Architecture

```
firebase/firestore.rules
  groups:      validGroup() checks settlementMode / settlementHubMemberId types and that
               the collector is a member document of the group; isArchived changes only
               by ownerUid; joining() refused while archived
  subcollections (members, expenses, settlements): create/update refused while archived
  users/{uid}: update of memberName only
lib/domain
  entities:    Group + settlementMode (enum SettlementMode { hub, simplified }), settlementHubMemberId
  failures:    GroupFailure.archived, GroupFailure.notOwner
  use cases:   CalculateDebts (mode-aware), SetGroupArchived, UpdateGroup (mode, collector),
               write use cases check archived; UserProfileRepository + watchMemberName / setMemberName
lib/data
  Drift v6:    groups.settlementMode, groups.settlementHubMemberId
  sync:        SyncCodec.group, puller _upsertGroup, mapper
  Firestore:   FirestoreUserProfileRepository memberName read/update + local cache
lib/presentation
  balances:    "Settling through An · Change" header, mode and collector picker sheet
  group:       settlement mode in group settings; owner menu Archive / Reopen; archived banner;
               read-only (no FAB, edit, add or settle actions)
  group list:  "Archived (n)" section; "All settled. Archive this group?" after the last settlement
  join:        "This group is archived"
  settings:    "My name" field (account section)
  forms:       prefill order for "Your name" (group form) and the join screen
```

## Phases

| Phase | Issue | PRs | Scope | Effort |
| --- | --- | --- | --- | --- |
| P1 Rules | #116, #117, #112 | 1 | The rules above, with tests in `firebase/test/` for each: valid and invalid mode values, a collector that isn't a member, a non-owner archiving, writes into an archived group (refused) and deleting it (allowed), joining an archived group, updating `memberName` (owner only, only that field, consent unchanged). Merging deploys the rules to dev only | 1 day |
| P2 Settlement mode | #116 | 1–2 | Entity, Drift v6 migration, codec, puller, mapper; hub algorithm with unit tests (nets sum to 0; collector with positive, negative and zero net; a member at 0 gets no suggestion; collector removed → owner); `CalculateDebts` and `debtSummaryProvider` take the mode; new groups created with `hub`; balances header and picker; group settings; activity labels; events `tapChangeSettlementMode`, `tapPickCollector`; EN and VI | 2 days |
| P3 Archive | #117 | 1–2 | `SetGroupArchived` (owner only); archived checks in the write use cases with `GroupFailure.archived` and EN/VI messages; app bar menu (owner), confirm dialog with the unsettled warning, archived banner with Reopen, read-only screens; "Archived (n)" on the group list; the "All settled" prompt after a settlement; join screen message; events `tapArchiveGroup`, `tapReopenGroup`, `tapOpenArchived`; tests for archive and reopen through sync, the list, and refused writes; a UC-3 success criterion in `docs/product/use-cases.md` through `product-owner` | 2–3 days |
| P4 My name | #112 | 1 | `UserProfileRepository.watchMemberName` / `setMemberName` with the local cache; Settings field; prefill order on the group form and the join screen; event `tapSaveMyName` already exists, reuse if it fits, otherwise `tapSaveAccountName`; widget tests for the order; `docs-writer` check of the privacy policy | 1 day |

P1 merges first, so dev has the new rules while P2–P4 are built against them. P2, P3 and
P4 are independent of each other after P1. All four ship to production in one release:
`firebase_deploy` deploys the rules to prd together with the web app.

## Manual steps

- None in the console: the rules ship through `firebase_deploy`, and no new index is
  needed (no new queries).
- After P1 merges: check the dev deploy, then test archive, settlement mode and My name
  on the dev build as each phase lands.
- At release: say in the release notes (EN and VI) that new groups settle through the
  group owner by default and that finished groups can be archived.

## Risks

| Risk | Mitigation |
| --- | --- |
| Builds already released (2026.10.24) don't know about archiving. On a group archived by its owner, their edits are refused by the rules and set aside by the pusher (`markFailed`), so that device keeps an edit nobody else sees | Rare (it needs an archived group and an old build editing it), and it ends when the build updates; Play updates are at 100 %. The pusher already handles refused writes without blocking the queue |
| An old build renaming a group sends `isArchived: false` from its stale copy; if the owner archived it meanwhile, the change counts as un-archiving by a non-owner and is refused | Same as above: the edit is set aside, not applied, and the group stays archived |
| An old build drops the new fields when it writes the group | It can't: the pusher writes with `merge: true` and only sends the fields it knows, so `settlementMode` and `settlementHubMemberId` stay |
| The collector check in the rules costs one more document read per group write that changes the collector | Only on writes that set `settlementHubMemberId`; a few a month per group |
| Hub suggestions with no collector (owner never claimed a member, or left) | The balances screen asks to pick a collector instead of guessing; switching to "Fewest transfers" is always possible |
| `users/{uid}` updates were never allowed before; a mistake could let an account change its consent | The rule allows `memberName` only (`affectedKeys().hasOnly(['memberName'])`), and P1 tests that consent, email and createdAt can't change |
