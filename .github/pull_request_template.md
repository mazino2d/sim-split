## Summary
<!-- What changes and why, from the user's point of view. Link the issue: "Closes #123". -->

## Changes
<!-- Delete the lines that don't apply. -->
- **Domain:**
- **Data:**
- **Presentation:**
- **Other:**

## Screenshots
<!-- Before / after for UI changes. Delete this section otherwise. -->

## Testing
- [ ] `flutter analyze --fatal-infos`
- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `flutter test`
- [ ] Firestore rules tests (only if `firebase/firestore.rules` changed)
- [ ] Tried it in the app on: <!-- Android / web / iOS -->

## Checklist
- [ ] `lib/domain/` stays pure Dart; presentation does not import data
- [ ] Money stays in `int` cents
- [ ] New strings are in both `app_en.arb` and `app_vi.arb`
- [ ] Generated files were regenerated, not hand-edited
