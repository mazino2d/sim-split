#!/usr/bin/env bash
# Build the release web bundle, serve it and load it in headless Chromium.
# Pass --no-build to reuse an existing build/web.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
PORT="${SMOKE_PORT:-8787}"
OUT=build/tester
NODE_DIR=.dart_tool/tester-node
mkdir -p "$OUT"

if [[ "${1:-}" != "--no-build" ]]; then
  flutter build web --release
fi

if [[ ! -d "$NODE_DIR/node_modules/playwright" ]]; then
  echo "Installing Playwright into $NODE_DIR..."
  npm install --silent --prefix "$NODE_DIR" playwright >/dev/null
  (cd "$NODE_DIR" && npx playwright install chromium >/dev/null)
fi

python3 -m http.server "$PORT" --directory build/web >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
sleep 1

NODE_PATH="$NODE_DIR/node_modules" node .claude/skills/e2e-tester/scripts/smoke_web.cjs \
  "http://localhost:$PORT/" "$OUT/web-release.png"
