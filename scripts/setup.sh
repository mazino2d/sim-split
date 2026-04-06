#!/usr/bin/env bash
# Bootstrap script — run once after cloning to initialize the Flutter project.
# Requires Flutter to be installed: https://flutter.dev/docs/get-started/install
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "📦 Creating Flutter project scaffold (preserving existing files)..."
cd "$PROJECT_DIR"

# Create the Flutter project structure (won't overwrite existing files)
flutter create \
  --org com.simsplit \
  --project-name simsplit \
  --platforms android,ios \
  .

echo "📥 Installing dependencies..."
flutter pub get

echo "🔨 Running code generators..."
dart run build_runner build --delete-conflicting-outputs

echo "🌐 Generating localizations..."
flutter gen-l10n

echo ""
echo "✅ Setup complete! Run the app with:"
echo "   flutter run"
echo ""
echo "📋 Next steps:"
echo "  1. Add your app icon to assets/icons/app_icon.png (1024×1024 PNG)"
echo "  2. Add your splash image to assets/images/splash_logo.png"
echo "  3. Run: dart run flutter_launcher_icons"
echo "  4. Run: dart run flutter_native_splash:create"
echo "  5. For Android signing: copy android/key.properties.example → android/key.properties"
echo "  6. For iOS: update YOUR_TEAM_ID in ios/ExportOptions.plist"
