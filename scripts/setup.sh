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
  --org com.mazino2d \
  --project-name simsplit \
  --platforms android,ios,web \
  .

echo "📥 Installing dependencies..."
flutter pub get

echo "🔨 Running code generators..."
dart run build_runner build --delete-conflicting-outputs

echo "🌐 Generating localizations..."
flutter gen-l10n

echo "🌍 Setting up web assets (Drift WASM + worker)..."
# Download the prebuilt release assets that match the versions locked in
# pubspec.lock, so the worker/WASM always match the Dart code they talk to.
locked_version() {
  # Prints the locked version of package $1 from pubspec.lock.
  awk -v pkg="  $1:" '
    $0 == pkg { found = 1; next }
    found && /^    version:/ { gsub(/"/, "", $2); print $2; exit }
  ' pubspec.lock
}

DRIFT_VERSION="$(locked_version drift)"
SQLITE3_VERSION="$(locked_version sqlite3)"
if [ -z "$DRIFT_VERSION" ] || [ -z "$SQLITE3_VERSION" ]; then
  echo "  ❌ Could not read drift/sqlite3 versions from pubspec.lock"
  exit 1
fi

curl -fsSL -o web/drift_worker.js \
  "https://github.com/simolus3/drift/releases/download/drift-${DRIFT_VERSION}/drift_worker.js"
echo "  ✅ Downloaded drift_worker.js (drift ${DRIFT_VERSION})"

curl -fsSL -o web/sqlite3.wasm \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${SQLITE3_VERSION}/sqlite3.wasm"
echo "  ✅ Downloaded sqlite3.wasm (sqlite3 ${SQLITE3_VERSION})"

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
