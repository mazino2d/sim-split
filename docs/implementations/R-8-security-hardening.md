# R-8 Security hardening — implementation plan

Status: shipped in 2026.11.23 (P1–P6 done; the CSP enforced on dev and prd)   ·   Spec: no spec document; the findings of the first `security-reviewer` scan (2026-11-21) are the scope   ·   Written 2026-11-21

How R-8 gets built. The first full scan with the
[`security-reviewer`](../../.claude/skills/security-reviewer/SKILL.md) skill found no
critical or high finding: nobody outside a group can read or change it. It found
weaker layers around that core: infrastructure settings that rely on App Check
alone, Firestore rules that trust members more than the app does, an unbounded
telemetry path, missing web headers, and loosely pinned CI actions. R-8 closes them,
infrastructure first because it guards everything else.

Work spans this repo and `mazino2d/everything-as-code` (infrastructure).

## Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Order | Infrastructure (P1) ships first, on dev, then prd; app-side phases follow in any order | P1 removes the ways around App Check, the layer every other phase leans on |
| Disclosure | This plan merges to `main` (and goes public on GitHub Pages) only after P1 is applied to prd | The repo is public; describing an open weakness before it is closed is a disclosure. Later phases are defence in depth, safe to describe while open |
| Debug tokens | App Check debug tokens exist on dev only. The prd stack drops the resources, not just the variable, so a token can't come back by setting a workspace variable | Debug builds run against dev (`APP_ENV=dev`); prd never needs one |
| API keys | Managed in Terraform (`google_apikeys_key`) with application restrictions (Android package + signing SHA-1s, iOS bundle id, web referrers) and only the APIs the app calls | Today the keys are created by Firebase and edited by hand, so their state can drift from `_docs/setup.md` without anyone noticing |
| Rule limits | Size limits in the rules match limits in the app's forms. Limits are generous (title 200, note 2 000 characters) so no real record breaks | A rule stricter than the form rejects a user's own save; a record over a new limit can still be read and deleted |
| Archived groups | The group document is read-only too, except: the owner reopening it, a member leaving, the last member deleting it | Matches the documented behaviour (#117): today only the records under the group are locked |
| Activity entries | Validated like other records: known `action` and `entityType` values, required fields, bounded sizes. Forged content stays possible for a member (the app writes it), but it always names its author | The history is append-only and signed by `actorUid`; full server-side derivation needs Cloud Functions, which this project avoids (cost) |
| Telemetry caps | Error reports get a daily cap per client address, kept only as a salted hash in the instance's memory (never logged or stored, reset daily and on restart), plus a global daily ceiling per instance for both endpoints | `report_id` is chosen per report, so the current cap does not bound a client. A stable install ID would make anonymous reports linkable across sessions, a privacy-policy change R-4 ruled out; an in-memory address cap needs no change to the app or the policy |
| CSP | Ships in report-only mode on dev first, enforced after a week without violations from real flows | A wrong CSP breaks sign-in, reCAPTCHA or the Flutter engine silently |

## Phases

| Phase | Repo | Scope | Effort |
| --- | --- | --- | --- |
| P1 Infrastructure | everything-as-code | Remove `google_firebase_app_check_debug_token` and `app_check_debug_token` from the prd stack (keep them on dev); delete the prd workspace variable. Add `google_apikeys_key` for the Android, iOS and Browser keys in both stacks: import the Firebase-created keys, restrict Android to `com.mazino2d.simsplit[.dev]` + the Play and upload SHA-1s, Browser to the environment's `*.web.app` and `*.firebaseapp.com`, and API targets to `firestore`, `identitytoolkit`, `securetoken`, `firebaseappcheck`, `firebaseinstallations` (plus `play.googleapis.com` / Play Integrity on Android if sign-in needs it). Drop `localhost` from prd's authorized domains. Replace the telemetry service account's `roles/bigquery.dataEditor` on `simsplit_raw` with a custom role that can only insert rows (`bigquery.tables.get`, `bigquery.tables.updateData`). Fix `_docs/setup.md` § 2.8, which says the key is already restricted. Apply on dev, check sign-in, sync and telemetry on the dev web app and the SimSplit [Dev] build, then prd | 1–1.5 days |
| P2 Firestore rules | sim-split | Archived group document read-only except reopen, leave and delete. String limits on `groups` (name already), `members` (name already), `expenses` (`title` ≤ 200, `note` ≤ 2 000, `category` from the enum), `settlements` (`note` ≤ 2 000), `activity` (allowed keys, `action` and `entityType` enums, `before` / `after` maps bounded by their keys). The same limits as `maxLength` in the expense and settlement forms. Tests in `firebase/test/` for each rule, including the cases the scan proved (a non-owner editing an archived group, a 900 KB title, an activity entry with unknown keys) | 1.5 days |
| P3 Telemetry | sim-split | `services/telemetry` caps error reports per client address per day (salted hash of the first `X-Forwarded-For` hop, in memory only) and adds a global per-instance daily ceiling for both endpoints; the 429 answer makes the app keep the reports queued, as for a 503. No app change. Tests in `services/telemetry` for each cap, and one that the address never reaches a log entry or a row | 1 day |
| P4 Web headers | sim-split | `firebase.json` `hosting.headers` for every path: `Referrer-Policy: strict-origin-when-cross-origin` (keeps invite tokens in `/join/<token>` out of referrers), `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY` and `frame-ancestors 'none'`, `Permissions-Policy` denying camera, microphone and geolocation. `Content-Security-Policy-Report-Only` with the sources the app needs (self, Firebase, Google sign-in, reCAPTCHA, gstatic fonts, the telemetry endpoint, `wasm-unsafe-eval`) on dev; enforced in a follow-up PR once clean. The `firebase_deploy` smoke test checks the headers | 1 day + a week of observation |
| P5 CI and dependencies | sim-split | Pin `actions/*` and `google-github-actions/*` to full commit SHAs with the version as a comment (Dependabot keeps them current, as for the actions already pinned); run `npm audit --omit=dev --audit-level=high` for `services/telemetry` in `pr_validate`; take the open moderate `glob` / `minimatch` alerts when `firebase-admin` releases a fix | 0.5 day |
| P6 Process | sim-split | `security-reviewer` in PR mode for every PR that touches `firebase/`, auth, `services/telemetry`, `.github/` or `AndroidManifest.xml` (a line in the `pr-writer` checklist); a full scan before each release that changes rules or infrastructure (a line in the `release-manager` preflight); `SECURITY.md` names the telemetry endpoint and the web headers in scope | 0.5 day |

Done so far: P1 in everything-as-code #255 and #256 (dev), #257 and #258 (prd), applied
2026-11-21 after sign-in and sync were checked on dev and prd; P2 in #167, P3 in #169,
P4 in #170 (headers on dev; the CSP report-only), P5 in #171, P6 in this repo's skills
and `SECURITY.md`. The CSP ran report-only on dev from 2026-11-21; its reports were
clean through sign-in, reCAPTCHA, sharing, saving images and web push, so it is
enforced on dev and prd since 2026-11-22. The first enforced deploy blocked the inline
scripts FlutterFire injects for the Firebase JS SDK (the reports had been missed);
`web/firebase_sdk.js` now loads the SDK as a file of our own, and the smoke test
fails on any CSP violation, report-only included. P2–P4 and the enforced CSP reached prd in
2026.11.23.

P2–P6 are independent of each other. P2 changes what released clients may write;
it is written so that builds already released keep working (see Risks).

## Manual steps

- P1, before apply: list the current keys (`gcloud services api-keys list --project
  <project>`) and note their IDs for the imports; check the Play App Signing and upload
  SHA-1s in Play Console.
- P1, after apply on each environment: sign in with Google on the web app and on
  Android; create and sync an expense; send a test error report from Diagnostics; check
  Firebase console → App Check → APIs shows no drop in verified requests.
- P4: read the CSP violation reports on dev for a week (sign-in, reCAPTCHA, sharing,
  saving images), then enforce.

## Risks

| Risk | Mitigation |
| --- | --- |
| A wrong key restriction breaks sign-in or sync for every user at once | Dev first, with the manual checks above; the prd apply is a separate PR, reverted by re-applying the previous key settings |
| A missing SHA-1 (debug, upload, Play signing) blocks Android sign-in for that build type | All three are listed in P1 and checked against Play Console before apply |
| A record already over a new size limit can no longer be edited | Limits are generous; check the longest titles and notes in the warehouse copy (`simsplit_raw`) before P2 merges; reading and deleting stay allowed |
| Many users behind one address (a carrier NAT, an office) share the P3 cap | The cap is per day and far above one device's error rate; the app keeps capped reports queued and retries the next day |
| Rules that check activity keys refuse an entry an older build writes in a shape the new rules don't expect | P2's tests replay the activity entries every released build writes; the pusher sets refused writes aside without blocking the queue |
| CSP blocks something only seen in production (a Google sign-in variant, a browser extension) | Report-only first; enforcement is a one-line revert |
