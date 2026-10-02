# SimSplit — CLAUDE.md

## Language Policy

**Always write in English** — all code, comments, documentation, commit messages, PR descriptions, and variable/function names must be in English. No exceptions.

---

## Project Overview

SimSplit is a Flutter app for tracking and splitting group expenses. It works **offline-first** with no account required.

- **Flutter** (CI pins `3.41.x` stable) + Dart `>=3.5`
- **Bundle ID:** `com.mazino2d.simsplit`
- **Architecture:** Clean Architecture — Domain (pure Dart) ← Data (Drift) ← Presentation (Riverpod)
- **Money:** always integer cents (`amountCents: int`), never `double`
- **Errors:** `Either<Failure, T>` from `fpdart`, not exceptions

---

## Commands

```bash
# Bootstrap (run once after installing Flutter)
bash scripts/setup.sh

# Code generation (run after modifying models/DAOs/providers)
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n

# Checks run by CI on every PR
flutter analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
flutter test --coverage

# Run app
flutter run
```

---

## Key Files

| File | Purpose |
| --- | --- |
| `lib/core/di/injection.dart` | DI wiring: DB → DAO → Repository → UseCase |
| `lib/domain/use_cases/expenses/calculate_splits.dart` | Pure domain: 4 split types |
| `lib/domain/use_cases/settlements/calculate_debts.dart` | Greedy debt simplification algorithm |
| `lib/data/database/app_database.dart` | Drift database root (all tables + DAOs) |
| `lib/presentation/router/app_router.dart` | go_router configuration |
| `.github/workflows/` | CI/CD: pr_validate, build_android, build_ios, release |

---

## Critical Rules

1. **The domain layer has ZERO dependency on Flutter/Drift/Riverpod.**
2. **Never use `double` for money — always `int` cents.**
3. **Never hand-edit generated files (`*.g.dart`, `*.freezed.dart`).**
4. **Never commit `android/key.properties`, `*.jks`, `AuthKey_*.p8`.**
5. **Test domain with Mocktail mocks, data layer with an in-memory Drift DB.**
6. **`group.members` is always empty — use `memberListProvider(groupId)` instead** (see [Known Pitfalls](#known-pitfalls)).

---

## Architecture: Clean Architecture (strict)

```text
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

VND has no subunit, so all amounts are stored × 100 to keep the schema uniform with USD.

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

### Failures

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

After modifying any model, DAO, or provider, run `build_runner` and `flutter gen-l10n` (see [Commands](#commands)).
Generated files (`*.g.dart`, `*.freezed.dart`) are gitignored — never edit them manually.

---

## Localization

- String keys live in `lib/core/l10n/app_en.arb` (English) and `app_vi.arb` (Vietnamese).
- Add new strings to **both** ARB files.
- String values may be in the target locale language, but ARB **keys** must be English camelCase.
- Access via `AppLocalizations.of(context)!.stringKey`.

---

## Testing Guidelines

- Domain use cases: unit test with `mocktail` mocks of repository interfaces.
- Data repositories: use an in-memory Drift DB — do not mock the database.
- Critical test files: `calculate_splits_test.dart`, `calculate_debts_test.dart`.
- Test names must be descriptive English sentences.

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

## Known Pitfalls

### `group.members` is always empty — use `memberListProvider` instead

`GroupMapper.toEntity()` maps only the `groups` table row and does **not** join the members table,
so `group.members` is always `[]` regardless of what is in the database.

**Never** access `group.members` in the presentation layer.
**Always** use `memberListProvider(groupId)` — a live Drift stream — to read member data:

```dart
// CORRECT — reactive, always up-to-date
final members = ref.watch(memberListProvider(groupId)).valueOrNull ?? [];

// WRONG — always empty list
final members = group.members;
```

This applies everywhere: member count badges, expense form dropdowns, split input rows, etc.

---

## CI/CD

| Workflow | Trigger | Result |
| --- | --- | --- |
| `pr_validate` | Every PR → `main` | Parallel jobs: format, analyze, test (shared setup in `.github/actions/flutter-setup`) |
| `build_android` | Push → `main` | AAB → Play Store internal track |
| `build_ios` | Push → `main` | IPA → TestFlight |
| `release` | `git tag v1.0.0` | Production release to both stores |

To open a pull request, use the `/write-pr` skill (`.claude/skills/write-pr/`).
