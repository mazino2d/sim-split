# CI/CD

| Workflow | Trigger | Result |
| --- | --- | --- |
| `pr_validate` | Every PR → `main` | Parallel format/analyze/test, store-metadata check and actionlint, each skipped unless its files change; required check: `PR Validation` |
| `build_android` | Manual, or called by `release` | AAB → Play Store (internal track by default) |
| `build_ios` | Manual | Unsigned iOS build (signing disabled until the Apple account is active) |
| `release` | `git tag v1.0.0` | Production release to both stores |
| `play_metadata` | Push → `main` touching `android/fastlane/metadata/**`, or manual (dry run) | Syncs Play store listing, images, contact, Data safety (see `android/fastlane/README.md`) |

Release tags must match the `version` in `pubspec.yaml`.
