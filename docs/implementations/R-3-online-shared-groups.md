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
| Firebase config | `lib/firebase_options.dart` is committed (generated from the Firebase Management API, like `flutterfire configure`). Firebase is initialised on Android and iOS only; web and desktop stay local-only | The API keys are app identifiers, not secrets. Access is enforced by security rules, and the keys get restricted to the app's package and bundle in everything-as-code. A web build would need its own Firebase app and is out of scope. |
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
  Drift (schema v3): every table gains updatedAt, deleted, createdBy, updatedBy;
                     members gain linkedUid; new outbox and activity tables
  Drift repositories: each write also inserts an outbox row and an activity row in the
                      same Drift transaction; hard deletes become soft deletes
  sync/ pusher:  drains the outbox in order → Firestore batch (entity + activity)
        puller:  one listener per group, filtered on updatedAt > cursor → upsert into
                 Drift, skipping records that still have pending outbox rows
  Firebase repositories: auth, invites, activity (all behind domain interfaces)
  Member.isMe: derived in the mapper as linkedUid == current uid

Firestore
  users/{uid}
  invites/{token}                    groupId (get by token only, never listed)
  groups/{g}                         memberUids[], ownerUid, inviteToken, updatedAt, deleted
  groups/{g}/members/{m}             linkedUid?, updatedAt, deleted
  groups/{g}/expenses/{e}            splits embedded, createdBy, updatedBy, updatedAt, deleted
  groups/{g}/settlements/{s}
  groups/{g}/activity/{a}            create-only: actor, action, entity, before, after, clientTime
```

Security rules, in short:
- Only users in `memberUids` can read or write a group and its subcollections.
- A signed-in user may add only their own uid to `memberUids`, and only when the token
  they send matches the group's current `inviteToken`.
- `activity` documents can be created but never updated or deleted.
- Every amount must be an integer.

## Phases

| # | Repo | Scope | Spec ACs | Days |
| --- | --- | --- | --- | --- |
| P0 ✅ | everything-as-code | Done in everything-as-code#214. Firebase stack: project, APIs, Firestore, Identity Platform (Google; Apple once the account is active), Android/iOS apps, Hosting site, WIF deployer, budget, kill switch | — | 2 |
| P1 | sim-split | Foundations (project config, rules deploy workflow and a deny-all ruleset landed with this plan): fix the iOS bundle id (`com.simsplit.simsplit` → `com.mazino2d.simsplit`), Podfile for iOS 15, Firebase packages, `firebase_options.dart` (from `flutterfire configure`), `firebase.json`, rules + rules tests on the emulator in `pr_validate`, a deploy workflow for rules, indexes and Hosting | AC23 | 2 |
| P2 | sim-split | Auth: domain interfaces and use cases, Firebase implementation, sign-in screen, the router as a provider with an auth redirect, an account section in Settings, sign-out wipes Drift, delete account. The e2e suite moves to the Auth emulator | AC1–AC6 | 3 |
| P3 | sim-split | Schema v3 and push: migration, soft deletes, outbox and activity tables, the pusher, uploading existing local data on first sign-in, claiming your member | AC7, AC8, AC16, AC29 | 4 |
| P4 | sim-split | Pull and realtime: listeners, upsert, "not synced yet" mark, convergence | AC15, AC17–AC22 | 3 |
| P5 | both | Invites: tokens, the join page and `.well-known` files on Hosting, App Links / Universal Links, the join screen, leave, reset link | AC9–AC14 | 3 |
| P6 | sim-split | Activity screen: the list and an old → new detail view | AC25–AC28, AC30 | 2 |
| P7 | both | iOS: Apple Developer account, Sign in with Apple, signing, TestFlight in `release.yml` | AC1b | 2 |
| P8 | sim-split | Release: e2e on emulators, the cost load test, a rewritten store listing (EN/VI), Data safety, privacy policy, v2.0.0 | AC20, AC24 | 2 |

The total is about 23 focused days. P5 and P6 can run in parallel after P4. P7 can start
whenever the Apple account is active.

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
| The Apple Developer account is not active in time | Ship Android with Google sign-in first (P7 later). |
| The kill switch takes the app offline | It only fires at 100 % of a tiny budget. Recovery is a re-apply after fixing the cause (see setup doc). |
| Budget notifications lag actual spend | Keep reads incremental (`updatedAt > cursor`). The P8 load test checks for ≥ 2× headroom. |
| The e2e suite breaks once sign-in is required | Move it to the Firebase emulators in P2, before enforcing sign-in. |
| Migrating v1 data | Upload with the same IDs, make it resumable, and test with a v2 database fixture (AC7, AC8). |
