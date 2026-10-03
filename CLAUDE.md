# SimSplit — CLAUDE.md

SimSplit is a Flutter app for tracking and splitting group expenses — **offline-first**, no account required.
Flutter `3.41.x` (CI-pinned) + Dart `>=3.5` · bundle ID `com.mazino2d.simsplit` · Android on Google Play, iOS and web from source.

## Language Policy

**Always write in English** — code, comments, docs, commit messages, PR descriptions and identifiers. No exceptions.
(User-facing strings are localized in EN and VI ARB files.)

## Commands

```bash
bash scripts/setup.sh                                      # bootstrap once after installing Flutter
dart run build_runner build --delete-conflicting-outputs   # after changing models / DAOs / providers
flutter gen-l10n                                           # after changing ARB files
flutter analyze --fatal-infos                              # ┐
dart format --output=none --set-exit-if-changed .          # ├ what CI runs on every PR
flutter test --coverage                                    # ┘
flutter run                                                # run the app (-d chrome for web)
```

## Critical Rules

1. **Clean Architecture is strict:** `lib/domain/` is pure Dart — no Flutter, Drift, Riverpod or go_router imports.
2. **Money is `int` cents, never `double`.**
3. **Errors are `Either<Failure, T>`** (fpdart), not exceptions, in domain and data.
4. **Never hand-edit generated files** (`*.g.dart`, `*.freezed.dart`).
5. **Never commit secrets:** `android/key.properties`, `*.jks`, `AuthKey_*.p8`.
6. **`group.members` is always empty** — read members with `memberListProvider(groupId)`.

## Skills

| Task | Skill |
| --- | --- |
| Write or change code, tests, l10n | `software-engineer:dev` — architecture, patterns, design system, testing |
| Open a pull request | `software-engineer:write-pr` |
| Triage ideas, write specs, update the roadmap | `product-owner` — strategy in `docs/product/` (public on GitHub Pages) |
| App icon, splash, Play Store graphics | `design-assets` — SVG masters in `design/` |
