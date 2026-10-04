# R-1 Offline app (v1.0) — implementation

Status: shipped   ·   Spec: [R-1 Offline app](../product/specs/R-1-offline-app.md)   ·   Backfilled 2026-10-04 from commit and PR history

How v1.0 was built: the architecture, the technical decisions, and the hardening that
made it releasable.

## Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Framework | Flutter (Android, iOS, web from one codebase) | One codebase. Web gives a fast dev loop and a browser-driven e2e suite. |
| Architecture | Strict Clean Architecture: `presentation → domain ← data` | Domain logic (splits, debts) is pure Dart and testable without Flutter or a database. |
| Local store | Drift (SQLite), WASM worker + OPFS/IndexedDB on web | Typed queries, reactive streams, migrations, the same code on every platform. |
| IDs | UUID text primary keys | No collisions if data ever leaves the device. R-3 relies on this. |
| State / DI | Riverpod with codegen: `AppDatabase → DAO → Repository → UseCase → Provider` in `lib/core/di/injection.dart` | Compile-time-safe wiring. Repositories are typed as domain interfaces, so implementations can be swapped. |
| Errors | `Either<Failure, T>` (fpdart); no bare throws in domain or data | Every failure is a value, and the UI maps it to a localised message (`failure_message.dart`). |
| Models | `@freezed` entities; Drift tables kept separate, with mappers | The domain never sees Drift types. |
| Money | `int` cents only (VND stored ×100 for a uniform schema) | No float rounding. Splits always sum to the total. |
| Navigation | go_router, every route nested under `/` | Back always returns to the group list instead of exiting the app. |
| Localisation | ARB files (EN, VI), `flutter gen-l10n` | Bilingual from day one. |

## Architecture

```
lib/domain        entities (Group, Member, Expense, ExpenseSplit, Settlement, Debt),
                  value objects (Money, UniqueId, Percentage), failures,
                  repository interfaces, use cases
                  key logic: calculate_splits.dart, calculate_debts.dart
lib/data          Drift tables (schema v2), DAOs, mappers, Drift repositories
lib/presentation  screens, widgets, providers (streams), notifiers (mutations), router
lib/core          DI, l10n, money formatting, constants
```

The key algorithms:
- **Equal split:** `total ~/ n`. The first `total % n` members get one extra cent.
- **Percentage and shares:** largest-remainder allocation. Everyone gets the floor, and
  the leftover cents go to the largest fractional remainders, with ties broken by input
  order. A 0-weight member never pays a cent.
- **Debt simplification:** greedy. The largest debtor pays the largest creditor until
  everyone is settled. At most N−1 transfers, deterministic given member order. Balances
  are always computed from expenses and settlements, never stored.
- **Deletes:** expenses are soft-deleted (`isDeleted`). Groups cascade-delete. A member
  who appears in any expense or settlement cannot be removed (`MemberFailure.hasHistory`).

## Build history

| When | PRs | What |
| --- | --- | --- |
| 2026-04-07 → 04-11 | first commits, #1 | Project setup, the four layers, groups, members, expenses, EN/VI, the payer dropdown, package `com.mazino2d.simsplit`, a first draft upload to Play (v1.0.0+5) |
| 2026-10-02 | #2 | Copilot instructions migrated to `CLAUDE.md`; `write-pr` skill |
| 2026-10-03 | #3 | **Domain hardening:** input validation in every use case, largest-remainder splits, no `!` lookups in debts, atomic expense + split writes, the currency locks once a group has expenses |
| 2026-10-03 | #5, #6, #7 | **Presentation fixes:** currency-aware money parsing (fixed "12.50" being stored as $1,250.00), the settlement flow saves exact suggested cents, nested routes, notifiers return `Either`, Save disabled while saving, localised failures, the web group form no longer hangs |
| 2026-10-03 | #4 | **Release prep:** uploads to Play only by manual dispatch or tag, versionCode = minutes since 2026-01-01 UTC, cloud backup disabled, release builds fail loudly without `key.properties` |
| 2026-10-03 | #8, #14 | **CI:** parallel format, analyze and test jobs; a shared `flutter-setup` action with SDK, pub and codegen caches; a path filter; a single required check `PR Validation`; actionlint |
| 2026-10-03 | #9 | **Keyless Play upload** through Workload Identity Federation (no JSON key secret) |
| 2026-10-03 | #10–#13 | **Store as code:** `scripts/play_metadata.py` (check and sync) plus the `play_metadata.yml` workflow; the listing, images and contact info live under `android/fastlane/metadata/` |
| 2026-10-03 | #15 | Settlement history and `DeleteSettlement` |

## Testing

- **Domain:** use-case unit tests with mocktail repository mocks.
- **Data:** repository tests against the real Drift repositories on an in-memory database
  (`AppDatabase.forTesting(NativeDatabase.memory())`). The database is never mocked.
- **Presentation:** widget tests with `ProviderScope` overrides.

## Lessons for later phases

- Most of the release effort was hardening. Validating at the domain boundary caught the
  money bugs before users did.
- Hard deletes and a per-device `isMe` were fine offline, but R-3 has to replace them with
  soft deletes and a member ↔ account link.
- Hand-written `if (from < N)` Drift migrations work for small steps. The R-3 schema v3
  change needs a migration test on a v2 fixture.
