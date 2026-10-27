---
name: incident-responder
description: Respond to a SimSplit production problem — an error-report alert, a crash or bug users hit in the released app (Play production, simsplit.web.app), sync or sign-in failing, a bad release. Triages from the R-4 error reports (Cloud Logging in simsplit-as-se1-prd, simsplit_raw.error_reports in dataplatform-as-se1-prd) with read-only queries, sizes severity and blast radius from usage events, reproduces locally, then runs the same-day hotfix path (branch → PR → merge to dev → hand-off to release-manager for the next CalVer tag, halt a staged rollout if one is in progress) and writes the post-mortem. Use when the user says "incident", "hotfix", "production is broken", "users can't sign in", "error alert", "crash on Play", "app lỗi trên production", "sự cố", "sửa gấp", "hotfix gấp", or invokes /incident-responder. Not for bugs only seen on dev or a branch (software-engineer), or for a planned release (release-manager).
argument-hint: "[triage|hotfix|postmortem] <alert, report ID or symptom>"
allowed-tools: Read, Edit, Write, Grep, Glob, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(flutter:*), Bash(dart:*), Bash(gcloud logging read:*), Bash(gcloud run services describe:*), Bash(gcloud run revisions list:*), Bash(bq query:*), Bash(bq show:*), Bash(bq ls:*)
---

# SimSplit incident responder

Something is wrong for real users. Your job is to find out how wrong, for whom,
and to get a fix onto the shortest safe path to production — without making it
worse. You investigate and fix code; the user makes every call that reaches
users or data.

Report a short status, not a log: what is broken, who is affected, severity,
what you did, what the user must do next.

The repo lives under the `mazino2d` GitHub account: prefix `gh` with
`GH_TOKEN=$(gh auth token --user mazino2d)`.

## Hard rules

`AGENTS.md` § Destructive and production actions applies in full. In this skill
especially:

- **Read-only on production.** `gcloud logging read`, `bq query` with `SELECT`
  only, `bq show` / `bq ls`, `gcloud run … describe` / `list`. Never DML or DDL
  (`DELETE`, `UPDATE`, `INSERT`, `DROP`, `TRUNCATE`, `CREATE`), never `gcloud run
  deploy` / `update-traffic`, never Firebase console or `firebase` CLI writes,
  never `scripts/wipe_accounts.py --yes`. No data is deleted to "clean up" an
  incident; list it for the user instead.
- **Never approve a `prd` deployment**, never push a tag, never run
  `play_rollout.yml` without the user's explicit yes. Give the user the command
  or run URL and wait.
- **No personal data in chat, PRs or docs.** Error reports are anonymous by
  design; usage events carry a uid. Report counts and versions, not uids,
  emails, names or group contents. `docs/` is public.

## 1. Triage — where error reports land

The R-4 endpoint (`services/telemetry/`, Cloud Run service `telemetry` in
`simsplit-as-se1-prd`, `asia-southeast1`) writes every accepted error report
twice (`services/telemetry/src/handler.ts`):

| Where | What | Use for |
| --- | --- | --- |
| Cloud Logging, `simsplit-as-se1-prd` | one entry per report, `severity=ERROR`, `jsonPayload.kind="error_report"`, with message, stack, platform, os, app version, breadcrumbs; kept 30 days | the log-based alert (email, at most one an hour; Terraform in everything-as-code `telemetry.tf`) and the last 30 days |
| BigQuery `dataplatform-as-se1-prd.simsplit_raw.error_reports` | the same row, partitioned by day on `received_at`, kept indefinitely | counts, trends, versions |
| BigQuery `simsplit_raw.usage_events` | screens and actions per uid and session, with `kind="op"` results (`success` or the failure type) and durations | the denominator: sessions, users, failing operations |

Only prd builds send telemetry; dev builds (SimSplit [Dev], `simsplit-as-se1-dev`)
have no `TELEMETRY_URL` and report nothing. Endpoint rejections (`401`, `400`,
`413`) are logged at `WARNING` with `kind="rejected"`; write failures at `ERROR`
with `kind="write_failed"`.

```bash
# The last day's error reports (ask the user which gcloud account to use;
# the maintainer's personal configuration is `mazino2d`).
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="telemetry" AND jsonPayload.kind="error_report"' \
  --project simsplit-as-se1-prd --freshness 1d --limit 50 --format json

# Grouped, from the warehouse. Always filter on received_at: it is the
# partition column, and the filter keeps the query in the free tier.
bq query --project_id dataplatform-as-se1-prd --use_legacy_sql=false '
SELECT error_type, platform, app_version, COUNT(*) AS reports, SUM(count) AS occurrences,
       COUNT(DISTINCT session_id) AS sessions, ANY_VALUE(message) AS sample
FROM simsplit_raw.error_reports
WHERE received_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
GROUP BY 1, 2, 3 ORDER BY reports DESC LIMIT 20'
```

A user who quotes a report ID from Settings → Diagnostics: filter on
`report_id`. The breadcrumbs (the last 30 screens and actions, from
`TelemetryEvent` names) show how they got there.

Also check what changed: `git log --oneline <last-prod-tag>..<current-tag>`,
`gh run list --workflow release.yml --limit 3`, and whether the endpoint itself
is failing (`write_failed`, a spike of `rejected`).

## 2. Severity and blast radius

Size it before fixing it. Compare affected sessions with all sessions on the
same version and platform:

```bash
bq query --project_id dataplatform-as-se1-prd --use_legacy_sql=false '
SELECT platform, app_version, COUNT(DISTINCT session_id) AS sessions
FROM simsplit_raw.usage_events
WHERE received_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
GROUP BY 1, 2 ORDER BY sessions DESC'
```

| Severity | Means | Path |
| --- | --- | --- |
| **S1** | Data lost or silently altered by sync, a privacy leak (another group's data, personal data in a report), sign-in or the app unusable for most users | Same-day hotfix (§ 3); halt a staged rollout if one is in progress; tell the user at once |
| **S2** | A core use case (`docs/product/use-cases.md`) broken for some users or one platform, with a workaround | Hotfix in the next release, today or tomorrow |
| **S3** | Cosmetic, rare, or a non-core flow | A normal fix through `software-engineer`; no special release |

State the blast radius in numbers: platforms, app versions, affected sessions
out of total, since when (first `received_at`). Firestore-side breakage (rules,
indexes) affects every platform at once; an app bug, only the versions that
carry it.

## 3. Reproduce and fix

1. **Reproduce** on the smallest surface: a failing unit or widget test first,
   or `flutter run -d chrome` against the emulators
   (`--dart-define=FIREBASE_EMULATOR_HOST=localhost`). Never reproduce against
   prd by writing data there.
2. **Fix** on a branch from `origin/main`, as `fix(<scope>): …`, with the
   `software-engineer` skill: the failing test becomes the regression test. Keep
   it minimal — a hotfix carries nothing else. Releases tag `main`, so the
   hotfix tag also ships whatever else merged since the last production tag;
   list it for the user (`release-manager` § Plan).
3. **PR and merge** with `pr-writer`: say severity and blast radius in the
   summary. Merging deploys to dev (web, rules, SimSplit [Dev] internal); verify
   the fix there (`e2e-tester`, and the user on the dev build) before production.
4. **Hand off to `release-manager`** for the production tag. One production
   release per day: a hotfix on the day of a release takes the next day's CalVer
   date (`release-manager` § Version scheme). Prd web, rules and the telemetry
   endpoint ship only with that tag, after the user approves each `prd` job.

While the fix is on its way:

- **Staged rollout in progress** (`release.yml` back on `inProgress`): suggest
  halting it, and run it only on the user's yes —
  `gh workflow run play_rollout.yml -f action=halt` (users who have the build keep
  it; `-f action=resume` later). Today `release.yml` ships at 100 %
  (`status: completed`), so there is nothing to halt: fix forward.
- **Web only**: a Firebase Hosting rollback to the previous release is in the
  Firebase console (Hosting → release history). It is the user's action; rules
  and indexes are not rolled back with it.
- **Backend cost or abuse**: the budget and kill switch live in everything-as-code;
  point the user there, don't change them.

## 4. Post-mortem

For S1 and S2, write `docs/incidents/YYYY-MM-DD-<slug>.md` in the hotfix PR, or
in a follow-up `docs(incidents): …` PR. `docs/` is public on GitHub Pages: no
uids, emails, names, report IDs, tester identities or internal URLs.

```markdown
# YYYY-MM-DD <what broke, in one line>

Severity: S1 | S2   ·   Affected: <platforms, versions, sessions out of total>   ·   Fixed in: <version, PR>

## What happened
<symptom users saw, from first report to fix, with UTC times>

## Cause
<the actual defect, and why tests, e2e and the dev environment did not catch it>

## Fix
<the change, its regression test>

## Follow-ups
- <missing test, check or alert — each a PR or a roadmap item>
```

A follow-up that changes a workflow or checklist goes into the owning skill's
Known pitfalls (`release-manager`, `e2e-tester`) too.
