# SimSplit — Copilot Instructions

## Language Policy

**Always write in English** — all code, comments, documentation, commit messages, PR descriptions, and variable/function names must be in English. This applies everywhere in the codebase, no exceptions.

---

## Project Overview

SimSplit is a Flutter app for tracking and splitting group expenses. It works **offline-first** with no account required. Bundle ID: `com.simsplit.app`.

---

## Architecture: Clean Architecture (strict)

```
Presentation  →  Domain  ←  Data
```

### Dependency Rules — enforce strictly

| Layer | Allowed imports | Must NOT import |
| --- | --- | --- |
| `lib/domain/` | dart:core, freezed_annotation, fpdart, uuid | flutter, drift, riverpod, go_router |
| `lib/data/` | domain/ + drift + path_provider | flutter/widgets, riverpod (except adapter) |
| `lib/presentation/` | domain/use_cases/ + flutter + riverpod + go_router | drift, DAO, mapper, table models |

### Layer Responsibilities

- **`lib/domain/`** — Pure Dart. Entities (`@freezed`), value objects, failures (`Either<Failure, T>`), repository interfaces (abstract), use cases.
- **`lib/data/`** — Drift tables (separate from domain entities), DAOs, mappers (`DriftRow ↔ DomainEntity`), repository implementations.
- **`lib/presentation/`** — Riverpod `StreamProvider`/`AsyncNotifier`, go_router screens, widgets.
- **`lib/core/di/injection.dart`** — DI chain: `AppDatabase → DAO → Repository → UseCase → Provider`.

---

## Key Patterns

### Money: always integer cents — never `double`

```dart
// CORRECT — integer cents
final amountCents = 50000 * 100; // 50,000 VND stored as 5,000,000 cents

// WRONG — never use double for money
final amount = 50000.0;
```

VND has no subunit, so all amounts are stored × 100 to maintain schema uniformity with USD.

### Error handling: `Either`, not exceptions

```dart
// CORRECT
Future<Either<Failure, Group>> createGroup(Group group);

// WRONG — no bare throws in domain/data layers
Future<Group> createGroup(Group group); // throws on error
```

### Use case pattern

```dart
class CreateGroup implements AsyncUseCase<Group, CreateGroupParams> {
  const CreateGroup({required GroupRepository groupRepository});

  @override
  Future<Either<Failure, Group>> call(CreateGroupParams params) async { ... }
}
```

### Repository: domain interface → data implementation

```dart
// Domain interface — no Drift types
abstract interface class GroupRepository {
  Stream<Either<Failure, List<Group>>> watchGroups();
}

// Data implementation — uses Drift, maps via GroupMapper
class DriftGroupRepository implements GroupRepository { ... }
```

### Riverpod provider → use case wiring

```dart
@riverpod
ListGroups listGroups(Ref ref) =>
    ListGroups(groupRepository: ref.watch(groupRepositoryProvider));

@riverpod
Stream<List<Group>> groupList(Ref ref) {
  return ref.watch(listGroupsProvider)(const NoParams()).map(
    (either) => either.fold((f) => throw Exception(f), (g) => g),
  );
}
```

---

## Failures

```dart
// Domain error
left(const GroupFailure.notFound())

// Infrastructure error
left(Failure.dbFailure(e.toString()))

// Success
right(entity)
```

---

## Code Generation

After modifying any model, DAO, or provider, run:

```bash
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

Generated files (`*.g.dart`, `*.freezed.dart`) are excluded from git — never edit them manually.

---

## Localization

- String keys live in `lib/core/l10n/app_en.arb` (English) and `app_vi.arb` (Vietnamese).
- Add new strings to **both** ARB files.
- String values in ARB files may be in the target locale language, but the ARB **keys** must be in English (camelCase).
- Access via `AppLocalizations.of(context)!.stringKey`.

---

## Testing Guidelines

- Domain use cases: unit test with `mocktail` mocks of repository interfaces.
- Data repositories: use an in-memory Drift DB — do not mock the database.
- Critical test files: `calculate_splits_test.dart`, `calculate_debts_test.dart`.
- Test method names must be descriptive English sentences.

---

## File Naming

| Type | Convention | Example |
| --- | --- | --- |
| Use cases | `verb_noun.dart` | `create_group.dart`, `calculate_debts.dart` |
| Screens | `noun_screen.dart` | `group_list_screen.dart` |
| Notifiers | `noun_notifier.dart` | `group_notifier.dart` |
| Drift repositories | `drift_noun_repository.dart` | `drift_group_repository.dart` |
| Mappers | `noun_mapper.dart` | `group_mapper.dart` |

---

## CI/CD

| Workflow | Trigger | Result |
| --- | --- | --- |
| `pr_validate` | Every PR → `main` | Lint + format + tests + stale check |
| `build_android` | Push → `main` | AAB → Play Store internal track |
| `build_ios` | Push → `main` | IPA → TestFlight |
| `release` | `git tag v1.0.0` | Production release to both stores |
