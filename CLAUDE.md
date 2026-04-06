# SimSplit — CLAUDE.md

> For full architecture guidelines, patterns, and conventions, see:
> **[.github/copilot-instructions.md](.github/copilot-instructions.md)**

## Quick Reference

- **Flutter 3.24** + Dart 3.5, offline-first, no auth
- **Bundle ID:** `com.simsplit.app`
- **Architecture:** Clean Architecture — Domain (pure Dart) ← Data (Drift) ← Presentation (Riverpod)
- **Money:** always integer cents (`amountCents: int`), never `double`
- **Errors:** `Either<Failure, T>` from `fpdart`, not exceptions

## Commands

```bash
# Bootstrap (run once after installing Flutter)
bash scripts/setup.sh

# Code generation (run after modifying models/DAOs/providers)
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n

# Run tests
flutter test

# Run app
flutter run
```

## Key Files

| File | Purpose |
|---|---|
| `lib/core/di/injection.dart` | DI wiring: DB → DAO → Repository → UseCase |
| `lib/domain/use_cases/expenses/calculate_splits.dart` | Pure domain: 4 split types |
| `lib/domain/use_cases/settlements/calculate_debts.dart` | Greedy debt simplification algorithm |
| `lib/data/database/app_database.dart` | Drift database root (all tables + DAOs) |
| `lib/presentation/router/app_router.dart` | go_router configuration |
| `.github/workflows/` | CI/CD: pr_validate, build_android, build_ios, release |

## Critical Rules

1. **Domain layer có ZERO dependency vào Flutter/Drift/Riverpod**
2. **Không dùng `double` cho tiền — luôn dùng `int` cents**
3. **Generated files (`*.g.dart`, `*.freezed.dart`) không sửa tay**
4. **Không commit `android/key.properties`, `*.jks`, `AuthKey_*.p8`**
5. **Test với Mocktail mock cho domain, in-memory Drift DB cho data layer**
