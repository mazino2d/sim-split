#!/usr/bin/env bash
# Runs once when the dev container is created: produces the gitignored
# generated sources so analyze, test and run work straight away.
set -euo pipefail

# The config volume is created root-owned on first mount.
sudo chown -R vscode:vscode /home/vscode/.claude

flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
npm ci --prefix firebase/test

[ -f .env.local ] || cp .env.example .env.local
