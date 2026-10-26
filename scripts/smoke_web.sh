#!/usr/bin/env bash
# Load the web app in headless Chromium and fail on uncaught errors, console
# errors or failed requests (scripts/smoke_web.cjs).
#   smoke_web.sh              build the release bundle, serve it, load it
#   smoke_web.sh --no-build   serve and load an existing build/web
#   smoke_web.sh <url>        load a deployed site (firebase_deploy.yml, dev)
# Screenshot at build/tester/web-release.png.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
PORT="${SMOKE_PORT:-8787}"
OUT=build/tester
NODE_DIR=.dart_tool/tester-node
mkdir -p "$OUT"

URL=""
case "${1:-}" in
  http://* | https://*) URL="$1" ;;
  --no-build) ;;
  *) flutter build web --release ;;
esac

if [[ ! -d "$NODE_DIR/node_modules/playwright" ]]; then
  echo "Installing Playwright into $NODE_DIR..."
  npm install --silent --prefix "$NODE_DIR" playwright >/dev/null
  # On CI the runner may lack Chromium's system libraries; --with-deps
  # installs them (needs sudo).
  (cd "$NODE_DIR" && npx playwright install ${CI:+--with-deps} chromium >/dev/null)
fi

if [[ -z "$URL" ]]; then
  python3 -m http.server "$PORT" --directory build/web >/dev/null 2>&1 &
  SERVER_PID=$!
  trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
  sleep 1
  URL="http://localhost:$PORT/"
fi

NODE_PATH="$NODE_DIR/node_modules" node scripts/smoke_web.cjs "$URL" "$OUT/web-release.png"
