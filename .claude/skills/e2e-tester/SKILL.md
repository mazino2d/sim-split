---
name: e2e-tester
description: Verify that a SimSplit branch or PR is safe to merge — that it still builds a working app on every platform and every user-facing feature in docs/product/use-cases.md still works end to end. Runs the CI gates, builds web (release) and Android, drives the real app through the integration_test/ journey in Chrome, smoke-loads the release bundle, and reports a go/no-go verdict per use case. Use when the user asks to "test", "QA", "verify before merge", "check the app still works", "is this PR safe to merge", after a dependency or Flutter SDK bump, or invokes /e2e-tester.
argument-hint: "[pr-number|branch] [--quick]"
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(git:*), Bash(gh:*), Bash(flutter:*), Bash(dart:*), Bash(.claude/skills/e2e-tester/scripts/*), Bash(lsof:*), Bash(kill:*)
---

# SimSplit E2E tester

The question this skill answers: **if this merges, does the app still build
and does every feature still work for a real user?** Unit and widget tests
(the CI `Test` job) mock the database and the router; this skill runs the real
app — real Drift database in the browser, real navigation, release build.

Report a verdict, not a log. Never call something verified that you did not
run; say what was skipped and why.

## 0. Target

- A PR number → `gh pr checkout <n>` (repo needs
  `GH_TOKEN=$(gh auth token --user mazino2d)`).
- A branch → check it out. Nothing given → the current working tree.
- Note what changed: `git diff --stat origin/main...HEAD`. It decides which
  extra checks apply (see step 5).

## 1. Prepare

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

Generated files are gitignored, so stale ones after a dependency bump cause
compile errors that are not in the PR (e.g. riverpod `runBuild` signature
mismatches). Always regenerate first.

## 2. CI gates

Same commands as `pr_validate`; all must pass.

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

`--quick` stops here plus step 4 (E2E). Otherwise continue.

## 3. Builds

| Platform | Command | Notes |
| --- | --- | --- |
| Web | `.claude/skills/e2e-tester/scripts/smoke_web.sh` | Release build, served, loaded in headless Chromium. Fails on JS errors, console errors, failed or 4xx requests. Screenshot at `build/tester/web-release.png` — look at it. |
| Android | `flutter build apk --debug` | Compile and Gradle check; no signing needed. The signed AAB is built in CI (`build_android`). `PKIX path building failed` means a TLS-inspecting proxy (corporate network, WARP) blocks Gradle downloads: report **skipped (network)**, not failed. |
| iOS | `flutter build ios --no-codesign` | Needs full Xcode. If only Command Line Tools are installed, report **skipped** — don't treat it as passed. |

## 4. End-to-end journey

```bash
.claude/skills/e2e-tester/scripts/e2e_web.sh
```

Runs every `integration_test/*_test.dart` with `flutter drive` in headless
Chrome against the real app, inside the Firebase Auth and Firestore emulators
(`firebase-tools` through `npx`; needs Java and Node). The app connects to
them through `--dart-define=FIREBASE_EMULATOR_HOST=localhost`, on the
`demo-simsplit` project, and the journey signs in with a fake Google token
that only the emulator accepts. It fetches a chromedriver that matches the
installed Chrome into `.dart_tool/chromedriver/` on first use.

[integration_test/app_test.dart](../../../integration_test/app_test.dart) has
one test per use case. They run in order on one database, and each one
relaunches the app, so later tests also prove that data survives a restart.

| Test | Covers |
| --- | --- |
| UC-7.1 | A fresh install opens on sign-in; signing in reaches the empty group list |
| UC-3 | Create a group with me plus two members |
| UC-1 | Log an expense with the default payer and equal split, check that the shares sum to the total, edit it |
| UC-2 + UC-4 | Two simplified debts, settle one, it leaves the suggestions |
| UC-1.5 | Swipe to delete an expense |
| UC-6 | Switching language and theme takes effect without a restart |
| UC-7.5 | The group reached Firestore (push sync), then sign-out returns to sign-in |
| UC-7.2 | Sign in again: the group is pulled back from Firestore, with the deleted expense still gone and the settlement back |
| UC-7.6 | Delete the account from Settings |

Reading failures:

- Output names the failing test (`Failure in method: UC-…`). A timeout
  message lists the texts that were on screen, so you can see where the
  app actually was.
- Messages are also written to `build/integration_response_data.json`.
- The script runs in **debug** mode on purpose: `enterText` does not reach
  text fields on web in profile or release mode, so a non-debug E2E run fails
  for test-harness reasons, not app reasons. Release-mode coverage comes from
  the smoke check in step 3.
- A failure is an app bug until proven otherwise. Reproduce it by hand
  (`flutter run -d chrome`) before touching the test. Only change the test
  when the UI changed on purpose, and say so in the report.

## 5. Change-specific checks

| If the diff touches | Also do |
| --- | --- |
| `drift` or `sqlite3` version in `pubspec.lock` | Re-download the web worker and WASM that match: run the web-assets block of `scripts/setup.sh`, then repeat steps 3–4. A mismatched `web/drift_worker.js` breaks storage on web only. |
| Flutter SDK pin (`.github/actions/flutter-setup`) | Install that SDK locally first; run everything. |
| A new screen or user flow | Add or extend a test in `integration_test/` for it (follow the existing helpers: `launch`, `openGroup`, `tapAndWait`, `waitFor`). |
| `lib/core/l10n/*.arb` | Switch to Vietnamese by hand and check the changed screens for truncation. |
| `lib/data/database/` (tables, migrations) | Run E2E on a database from `main`: run the journey on `main`, then check out the branch and relaunch **without** clearing browser storage (`flutter run -d chrome` with the same `--web-port`). Existing data must still load. |
| `android/`, `ios/`, `web/` | The matching build in step 3 is mandatory, not optional. |

## 6. Report

End with a verdict table. Keep it short; link failures to `file:line`.

```text
Verdict: ✅ safe to merge | ⚠️ merge with caveats | ❌ do not merge

| Check            | Result | Notes                        |
| ---------------- | ------ | ---------------------------- |
| Format / Analyze | ✅     |                              |
| Unit + widget    | ✅     | 119 passed                   |
| Web release      | ✅     | smoke clean, screenshot OK   |
| Android build    | ✅     | debug APK                    |
| iOS build        | ⏭️     | skipped: no Xcode            |
| UC-3 group setup | ✅     |                              |
| UC-1 expenses    | ✅     |                              |
| UC-2/4 settle    | ✅     |                              |
| UC-1.5 delete    | ✅     |                              |
| UC-6 settings    | ✅     |                              |
```

❌ when any gate, build or use case fails. ⚠️ when something was skipped or
needs a human check (iOS, a migration on device). For a PR, offer to post the
table as a PR comment — don't post it unasked.

## Not covered

No Android emulator or iOS simulator runs here. Mobile-only behaviour
(predictive back, haptics, native splash, keyboard insets) needs a device —
list it under caveats when the diff touches it.
