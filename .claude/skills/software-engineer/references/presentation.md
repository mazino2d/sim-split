# Presentation layer

## Providers → use cases

```dart
@riverpod
ListGroups listGroups(Ref ref) =>
    ListGroups(groupRepository: ref.watch(groupRepositoryProvider));

@riverpod
Stream<List<Group>> groupList(Ref ref) {
  return ref.watch(listGroupsProvider)(const NoParams()).map(
    (either) => either.fold((f) => throw FailureException(f), (g) => g),
  );
}
```

- Read streams with `ref.watch(xProvider).value ?? fallback` (Riverpod 3:
  `.value`, not `valueOrNull`).
- Mutations go through notifiers in `lib/presentation/notifiers/`, which
  return the use case's `Either` so callers never read `state` after an
  `await` (notifiers are auto-dispose).
- A form must `ref.watch` its mutation notifier on every build so it is not
  disposed mid-save.

## Design system

The UI is minimal monochrome. Use the system; never hard-code colours,
fonts or radii.

| Need | Use |
| --- | --- |
| Colours | `Theme.of(context).colorScheme` (ink/white/greys) |
| Owed / owe amounts | `context.money.positive` / `.negative`, or `MoneyText(..., signed: true)` |
| Any amount | `MoneyText` (tabular figures, currency-aware) |
| Person | `MemberAvatar` (neutral; emoji or initial) — never `avatarColorValue` |
| Group icon | `GroupGlyph` |
| Expense category | `ExpenseCategoryUi` (`icon`, `label(l10n)`) and `CategoryTile` |
| Section heading | `SectionLabel` |
| Empty list | `EmptyState` (icon, title, one-line hint, one action) |
| Spacing / radii | `AppTheme.gutter` (20), `radiusS/M/L` (12/16/24) |

Tokens live in `lib/presentation/theme/app_theme.dart`; typeface is the
bundled Be Vietnam Pro.

## UX rules

Follow `docs/product/principles.md` — **Calm** beats **Fast capture**:

- No pop-ups, coach marks or nags. Confirm only destructive actions.
- The primary action of a form is a full-width button above the keyboard,
  not an app-bar icon.
- Pick with one tap (chips, avatar pickers) instead of dropdowns.
- Optional fields stay optional; fall back to sensible defaults.
- Every new screen works in light and dark and at large font sizes.

## Routing

`lib/presentation/router/app_router.dart`. All routes nest under `/` so Back
from a group returns to the list. Pass small options as query parameters
(e.g. `…/edit?focus=title`), not `extra`, so they survive deep links.

## Localization

- Strings live in `lib/core/l10n/app_en.arb` and `app_vi.arb`; add every new
  key to **both**. Keys are English camelCase; values are written natively in
  each language.
- Append new keys at the end of the file; don't reformat the JSON.
- Access via `AppLocalizations.of(context)!.key`; run `flutter gen-l10n`.
