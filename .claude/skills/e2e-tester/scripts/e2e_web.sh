#!/usr/bin/env bash
# Run the integration_test/ suite against the real web build in headless
# Chrome. Fetches a chromedriver that matches the installed Chrome on first
# use and caches it under .dart_tool/chromedriver/.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
PORT="${CHROMEDRIVER_PORT:-4444}"
CACHE=.dart_tool/chromedriver

if [[ -n "${CHROMEDRIVER:-}" ]]; then
  DRIVER="$CHROMEDRIVER"
elif command -v chromedriver >/dev/null 2>&1; then
  DRIVER="$(command -v chromedriver)"
else
  case "$(uname -s)" in
    Darwin) CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ;;
    *) CHROME="$(command -v google-chrome || command -v chromium)" ;;
  esac
  MAJOR="$("$CHROME" --version | grep -oE '[0-9]+' | head -1)"
  DRIVER="$(find "$CACHE" -type f -name chromedriver -path "*${MAJOR}.*" 2>/dev/null | head -1 || true)"
  if [[ -z "$DRIVER" ]]; then
    echo "Fetching chromedriver $MAJOR..."
    npx -y @puppeteer/browsers install "chromedriver@$MAJOR" --path "$CACHE" >/dev/null
    DRIVER="$(find "$CACHE" -type f -name chromedriver -path "*${MAJOR}.*" | head -1)"
  fi
fi

"$DRIVER" --port="$PORT" >/dev/null 2>&1 &
DRIVER_PID=$!
trap 'kill $DRIVER_PID 2>/dev/null || true' EXIT
sleep 1

for target in integration_test/*_test.dart; do
  echo "▶ $target"
  flutter drive \
    --driver=test_driver/integration_test.dart \
    --target="$target" \
    -d web-server \
    --browser-name=chrome \
    --driver-port="$PORT" \
    --headless \
    "--${E2E_MODE:-debug}" \
    "$@"
done
