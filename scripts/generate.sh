#!/usr/bin/env bash
# Run all code generators: Drift, Freezed, Riverpod, and flutter_gen (l10n)
set -e

echo "🔨 Running build_runner..."
dart run build_runner build --delete-conflicting-outputs

echo "🌐 Generating localizations..."
flutter gen-l10n

echo "🎨 Generating launcher icons..."
dart run flutter_launcher_icons

echo "💫 Generating splash screens..."
dart run flutter_native_splash:create

echo "✅ Generation complete."
