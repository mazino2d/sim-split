# R-3 Co-worked groups — implementation plan

Status: ready   ·   Spec: [R-3 Co-worked groups](../product/specs/R-3-online-shared-groups.md)   ·   Written 2026-10-03

How R-3 gets built: the architecture, the phases (one or two PRs each) and the decisions
behind them. The spec defines *what* must be true. This plan defines *how* and in what
order.

## Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Backend | Firebase Auth (Identity Platform) + Cloud Firestore, `asia-southeast1` | Covers auth, database, realtime and security rules in one SDK, with free quotas far above 100 users. |
| Project | Dedicated GCP project `simsplit-as-se1-prd` | Keeps quotas, access and billing separate from the dev project. |
| Infrastructure as code | Stack `terraform/gcp/simsplit-as-se1-prd` in `mazino2d/everything-as-code` | Same Terraform Cloud flow as the rest of the infrastructure: plan on PR, apply on merge. |
| Plan and cost | Blaze, at a target of $0 | Identity Platform needs billing. Budget alerts at 50 % and 100 %, and a kill switch (budget → Pub/Sub → Cloud Function) unlinks billing at 100 %. |
| App-coupled config | `firestore.rules`, indexes and Hosting content live in this repo | They change together with the data model. CI deploys them on `main` through Workload Identity Federation as `gha-firebase-deployer`. |
| Local store | Drift stays the source of truth that the UI reads | Offline after sign-in, existing tests stay valid, and the domain layer is unchanged. |
| Firestore SDK cache | Disabled | Drift is the cache. Offline writes wait in the outbox instead of a second hidden queue. |
| Conflict ordering | Last write to reach the server wins; `updatedAt` is `serverTimestamp()` | Device clocks can be wrong, but server arrival order cannot. |
| Audit | Each change is written in one Firestore batch: the entity plus an `activity` doc | A change can never sync without its history entry (AC29). Rules allow `create` only on `activity`. |
| Invite links | App Links / Universal Links on Firebase Hosting (`simsplit.web.app/join/<token>`) | Firebase Dynamic Links is shut down. Hosting serves the fallback page and the `.well-known` files. |
| Firebase config | `lib/firebase_options.dart` is committed (generated from the Firebase Management API, like `flutterfire configure`). Firebase is initialised on Android and iOS from P1 and on web from P4; desktop stays local-only | The API keys are app identifiers, not secrets. Access is enforced by security rules, and the keys get restricted to the app's package, bundle and web origin in everything-as-code. Web gets its own Firebase app in P4, right after push, because the web build is the fastest place to test: the e2e journey and manual checks run in Chrome without a device or a Play build. |
| Web parity | From P4 onwards, every phase ships on Android and web together, and the web e2e journey covers it against the emulators | A feature that works on Android but not on web cannot be tested end to end in CI. |
| Platforms | Android first if the Apple Developer account is not active in time | Apple sign-in and iOS signing both need the account. |

## Architecture

```
lib/domain      (pure Dart)
  + entities: AuthUser, ActivityEntry, Invite
  + repositories: AuthRepository, InviteRepository, ActivityRepository, SyncStatusRepository
  + use cases: SignInWithGoogle/Apple, SignOut, DeleteAccount, CreateInvite, ResolveInvite,
               JoinGroup, LeaveGroup, ResetInvite, WatchActivity, WatchSyncStatus
  existing use cases unchanged

lib/data
  Drift (schema v3): groups, members, expenses and settlements gain createdBy, updatedBy
                     and a tombstone (expenses keep isDeleted); members gain linkedUid;
                     new activities, outbox_entries and sync_states tables
  Drift repositories: each write also inserts an activity row (before/after JSON) and an
                      outbox row in the same Drift transaction (SyncRecorder), only while
                      signed in; hard deletes become soft deletes
  sync/ uploader: on first sign-in per account, queues every local record as a create,
                  in one transaction with its "done" marker (AC7, AC8)
        pusher:  drains the outbox in order, one group per Firestore batch (entity set
                 with merge + activity create); a batch the rules reject is resolved by
                 dropping entries whose activity doc already exists (pushed before a
                 restart) or setting the oldest entry aside
        puller:  one listener per group, filtered on updatedAt > cursor → upsert into
                 Drift, skipping records that still have pending outbox rows
  Firebase repositories: auth, invites, activity (all behind domain interfaces)
  Member.isMe: stays a local column. Marking a member as me links it (linkedUid = uid)
               and releases the previous one; P5 sets isMe from linkedUid when pulling

Firestore
  users/{uid}
  invites/{token}                    groupId (get by token only, never listed)
  groups/{g}                         memberUids[], ownerUid, inviteToken, updatedAt, deleted
  groups/{g}/members/{m}             linkedUid?, updatedAt, deleted
  groups/{g}/expenses/{e}            splits embedded, createdBy, updatedBy, updatedAt, deleted
  groups/{g}/settlements/{s}
  groups/{g}/activity/{a}            create-only: actor, action, entity, before, after,
                                     clientTime, syncedAt
  Dates are epoch milliseconds; local-only fields (isMe, device updatedAt) are not synced
```

Security rules, in short:
- Only users in `memberUids` can read or write a group and its subcollections.
- A signed-in user may add only their own uid to `memberUids`, and only when the token
  they send matches the group's current `inviteToken`.
- `activity` documents can be created but never updated. They are deleted only together
  with a group whose last member deletes their account (AC6).
- A member can be claimed only while unclaimed and only by yourself; a member may leave
  (remove only their own uid) and an owner who leaves hands ownership to a remaining member.
- Every amount must be an integer.

## Phases

| # | Repo | Scope | Spec ACs | Days |
| --- | --- | --- | --- | --- |
| P0 ✅ | everything-as-code | Done in everything-as-code#214. Firebase stack: project, APIs, Firestore, Identity Platform (Google; Apple once the account is active), Android/iOS apps, Hosting site, WIF deployer, budget, kill switch | — | 2 |
| P1 ✅ | sim-split | Done in #32 (project config, deploy workflow, deny-all ruleset) and #34. Foundations: fix the iOS bundle id (`com.simsplit.simsplit` → `com.mazino2d.simsplit`), Podfile for iOS 15, Firebase packages, `firebase_options.dart` (from `flutterfire configure`), `firebase.json`, rules + rules tests on the emulator in `pr_validate`, a deploy workflow for rules, indexes and Hosting | AC23 | 2 |
| P2 ✅ | sim-split | Done in #35. Auth: domain interfaces and use cases, Firebase implementation, sign-in screen, the router as a provider with an auth redirect, an account section in Settings, sign-out wipes Drift, delete account. The gate applies only where Firebase is initialised (Android, iOS), so the web e2e journey runs unchanged; sign-in is covered by unit and widget tests. The cloud side of AC6 (leaving groups, deleting groups where the user is the only member) lands with P3, once groups are in Firestore | AC1–AC6 | 3 |
| P3 ✅ | sim-split | Done in #36. Schema v3 and push: migration, soft deletes, outbox and activity tables, the pusher, uploading existing local data on first sign-in, claiming your member (an inline "Which one is you?" card, asked once, for groups with several members and no "me"), the cloud side of delete account, Firestore rules for groups. Sign-out refuses while changes are unsynced | AC6, AC7, AC8, AC16, AC29 | 4 |
| P4 | both | Web parity: a Firebase Web app with `simsplit.web.app` and `localhost` in the authorized domains (everything-as-code), web `FirebaseOptions`, Firebase initialised on web so the sign-in gate and push sync from P3 run there exactly as on Android, a web `AuthRepository` implementation (`signInWithPopup` for Google; Apple waits for P8), account deletion on web (the web account-deletion path Play requires), and the web e2e journey signing in against the Auth and Firestore emulators | AC1–AC8, AC16, AC29 on web | 3 |
| P5 | sim-split | Pull and realtime: listeners, upsert, "not synced yet" mark, convergence, on Android and web | AC15, AC17–AC22 | 3 |
| P6 | both | Invites: tokens, the join page and `.well-known` files on Hosting, App Links / Universal Links, the join screen, leave, reset link. On web, the join page opens the group in the web app | AC9–AC14 | 3 |
| P7 | sim-split | Activity screen: the list and an old → new detail view | AC25–AC28, AC30 | 2 |
| P8 | both | iOS: Apple Developer account, Sign in with Apple (iOS, Android and web through the Services ID), signing, TestFlight in `release.yml`. Move `build_ios.yml` to `macos-15`: firebase-ios-sdk 12 needs Xcode 16.3+ (Swift tools 6.1), so the iOS CI build fails on `macos-14` from P1 onwards | AC1b | 2 |
| P9 | both | Release: App Check (register the Android app with the Play Integrity provider in everything-as-code, `firebase_app_check` in the app with the debug provider for debug builds and CI, then enforce on Firestore and Auth; v2.0.0 is the first release that talks to Firebase, so enforcing at launch locks out no installed version; reCAPTCHA Enterprise for web; App Attest for iOS once P8 is done), e2e on emulators for Android, the cost load test, a rewritten store listing (EN/VI), Data safety, privacy policy, v2.0.0 | AC20, AC24 | 3 |

The total is about 27 focused days. P4 comes first after P3 so every later phase can be
tested in Chrome. P6 and P7 can run in parallel after P5. P8 can start whenever the Apple
account is active.

## Manual steps (no API or Terraform support)

These are listed in the stack's `_docs/setup.md` in `everything-as-code`:

1. Create the project, the Terraform service account and its key, and the TFC workspace.
   Import the project.
2. Grant the Terraform service account `billing.user` and `billing.costsManager` on the
   billing account.
3. Create the OAuth consent screen and a Web OAuth client for Google sign-in. Set them as
   TFC variables.
4. Add the Android SHA-1 and SHA-256 fingerprints for the upload key and the Play App
   Signing key.
5. Later, for Apple: the Services ID, the Sign in with Apple key and a client-secret JWT.
   The JWT must be rotated at least every 6 months.

## Risks

| Risk | Mitigation |
| --- | --- |
| The Apple Developer account is not active in time | Ship Android with Google sign-in first (P8 later). |
| The kill switch takes the app offline | It only fires at 100 % of a tiny budget. Recovery is a re-apply after fixing the cause (see setup doc). |
| Budget notifications lag actual spend | Keep reads incremental (`updatedAt > cursor`). The P9 load test checks for ≥ 2× headroom. |
| A script uses the public Firebase config to spam Firestore or Auth, trips the kill switch and takes the backend down for everyone | App Check, enforced on Firestore and Auth from v2.0.0 (P9), rejects requests that do not come from the genuine app. |
| The e2e suite breaks once sign-in is required | Until P4 the web build has no Firebase and so no sign-in gate; the e2e journey keeps running there (P2). From P4 it signs in against the Auth and Firestore emulators. |
| Migrating v1 data | Upload with the same IDs, make it resumable, and test with a v2 database fixture (AC7, AC8). |
