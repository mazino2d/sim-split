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

echo "🌍 Setting up web assets (Drift WASM + worker)..."
# Copy sqlite3.wasm from the drift devtools extension bundled in the pub cache
PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
DRIFT_DIR="$(find "$PUB_CACHE/hosted/pub.dev" -maxdepth 1 -name "drift-*" -type d 2>/dev/null | sort -V | tail -1)"
if [ -n "$DRIFT_DIR" ] && [ -f "$DRIFT_DIR/extension/devtools/build/sqlite3.wasm" ]; then
  cp "$DRIFT_DIR/extension/devtools/build/sqlite3.wasm" web/sqlite3.wasm
  echo "  ✅ Copied sqlite3.wasm from $(basename "$DRIFT_DIR")"
else
  echo "  ⚠️  Could not find drift package in pub cache ($PUB_CACHE) — run 'flutter pub get' first"
fi

# Compile the Drift web worker (requires a temporary entry file)
cat > /tmp/_drift_worker_entry.dart << 'DART'
import 'package:drift/wasm.dart';
void main() { WasmDatabase.workerMainForOpen(); }
DART
# Compile from the project context so package:drift resolves correctly
cp /tmp/_drift_worker_entry.dart lib/_drift_worker_entry.dart
dart compile js -O2 -o web/drift_worker.js lib/_drift_worker_entry.dart
rm lib/_drift_worker_entry.dart /tmp/_drift_worker_entry.dart
echo "  ✅ Compiled drift_worker.js"

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
