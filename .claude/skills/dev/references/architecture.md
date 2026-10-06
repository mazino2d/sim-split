# Architecture: Clean Architecture (strict)

```text
Presentation  →  Domain  ←  Data
```

## Dependency rules

| Layer | Allowed imports | Must NOT import |
| --- | --- | --- |
| `lib/domain/` | dart:core, freezed_annotation, fpdart, uuid | flutter, drift, firebase / cloud_firestore, riverpod, go_router |
| `lib/data/` | domain/ + drift + path_provider + firebase_auth / cloud_firestore | flutter/widgets, riverpod (except adapter) |
| `lib/presentation/` | domain/use_cases/ + flutter + riverpod + go_router | drift, DAO, mapper, table models |

## Layer responsibilities

- **`lib/domain/`** — Pure Dart. Entities (`@freezed`), value objects,
  failures, repository interfaces (abstract), use cases.
- **`lib/data/`** — Drift tables (separate from domain entities), DAOs,
  mappers (`DriftRow ↔ DomainEntity`), repository implementations.
  `lib/data/database/app_database.dart` is the Drift root (all tables + DAOs).
  Firebase-backed repositories (`firebase_auth_repository`,
  `firestore_invite_repository`, `firestore_sync_repository`) and the sync
  engine in `lib/data/sync/` live here too.
- **`lib/presentation/`** — Riverpod providers/notifiers, go_router screens,
  widgets.
- **`lib/core/di/injection.dart`** — DI chain:
  `AppDatabase → DAO → Repository → UseCase → Provider`.

Key domain logic: `use_cases/expenses/calculate_splits.dart` (4 split types)
and `use_cases/settlements/calculate_debts.dart` (greedy debt
simplification).

## Sync: Drift first, Firestore behind it

Drift is the source of truth for the UI and the only cache; the Firestore
offline cache is disabled. A write never goes to Firestore directly:

1. A repository writes the row and calls `SyncRecorder` **in the same Drift
   transaction**, which adds an activity entry (who, when, before → after) and
   an outbox entry. A change is never stored without its history.
2. `FirestoreSyncPusher` drains the outbox oldest-first, writing each change
   with its activity entry in one batch.
3. `FirestoreSyncPuller` listens to the account's groups and writes remote
   changes straight into Drift (never into the outbox). Last write to reach
   the server wins; records with pending outbox changes are skipped.
4. `SyncCodec` maps rows to Firestore maps: money stays integer cents, dates
   are epoch ms, local-only columns (`isMe`, device `updatedAt`) stay local.

When you add a synced field or table: extend `SyncCodec` both ways, record it
through `SyncRecorder`, update `firebase/firestore.rules` and its test in
`firebase/test/`, and keep pushes idempotent (same IDs). Nothing is recorded
while signed out; `LocalDataUploader` uploads it all on first sign-in.

## Money: integer cents, never `double`

```dart
// CORRECT — integer cents
final amountCents = 50000 * 100; // 50,000 VND stored as 5,000,000 cents

// WRONG
final amount = 50000.0;
```

VND has no subunit, but every amount is stored ×100 to keep the schema
uniform with USD. Parse and format only through
`lib/core/utils/money_formatter.dart` (`parseMoneyToCents`, `formatMoney`,
`formatCentsForInput`). Splits must always sum exactly to the total.

## Errors: `Either`, not exceptions

```dart
// CORRECT
Future<Either<Failure, Group>> createGroup(Group group);

// WRONG — no bare throws in domain/data
Future<Group> createGroup(Group group);
```

```dart
left(const GroupFailure.notFound())          // domain error
left(Failure.dbFailure(e.toString()))        // infrastructure error
right(entity)                                // success
```

New failures need a localized message in
`lib/presentation/utils/failure_message.dart`.

## Use case

```dart
class CreateGroup implements AsyncUseCase<Group, CreateGroupParams> {
  const CreateGroup({required GroupRepository groupRepository});

  @override
  Future<Either<Failure, Group>> call(CreateGroupParams params) async { ... }
}
```

## Repository: domain interface → data implementation

```dart
// Domain — no Drift types
abstract interface class GroupRepository {
  Stream<Either<Failure, List<Group>>> watchGroups();
}

// Data — uses Drift, maps via GroupMapper
class DriftGroupRepository implements GroupRepository { ... }
```

## Generated files

`*.g.dart` and `*.freezed.dart` are generated and gitignored — never edit
them; rerun `build_runner`.

## Pitfall: `group.members` is always empty

`GroupMapper.toEntity()` maps only the `groups` row and does not join
members, so `group.members` is always `[]`. Read members with
`memberListProvider(groupId)` (a live Drift stream) everywhere:

```dart
final members = ref.watch(memberListProvider(groupId)).value ?? [];
```
