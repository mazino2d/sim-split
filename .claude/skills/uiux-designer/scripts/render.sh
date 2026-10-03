#!/usr/bin/env bash
# Render an SVG or HTML file to a PNG of an exact size with headless Chrome.
# Transparent background is preserved. Fonts can be loaded with @font-face
# pointing at file:///…/assets/fonts/*.ttf.
#
# Usage: render.sh <input.svg|input.html> <output.png> <width> <height> [--opaque]
#
# --opaque drops the alpha channel (24-bit PNG). Play requires it for the
# feature graphic and screenshots; iOS requires it for the app icon.
set -euo pipefail

in="$1"; out="$2"; w="$3"; h="$4"; opaque="${5:-}"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[[ -x "$chrome" ]] || { echo "Chrome not found; set CHROME=/path/to/chrome" >&2; exit 1; }

abs_in="$(cd "$(dirname "$in")" && pwd)/$(basename "$in")"

# Chrome draws an SVG at its own width/height, so a 1024 master rendered into
# a 512 window would be cropped, not scaled. When the sizes differ, wrap the
# SVG in a page that scales it. (Fonts don't load inside <img>, so SVGs with
# text must be rendered at their own size — as the feature graphics are.)
if [[ "$abs_in" == *.svg ]]; then
  intrinsic="$(python3 - "$abs_in" <<'PY'
import re, sys
head = open(sys.argv[1], encoding="utf-8").read(2000)
m = re.search(r'<svg[^>]*\bwidth="(\d+)"[^>]*\bheight="(\d+)"', head)
print(f"{m.group(1)}x{m.group(2)}" if m else "")
PY
)"
  if [[ "$intrinsic" != "${w}x${h}" ]]; then
    wrapper="$(mktemp -d)/scaled.html"
    printf '<!doctype html><html><body style="margin:0"><img src="file://%s" style="display:block;width:%spx;height:%spx"></body></html>' \
      "$abs_in" "$w" "$h" > "$wrapper"
    abs_in="$wrapper"
  fi
fi
mkdir -p "$(dirname "$out")"
abs_out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"

"$chrome" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --default-background-color=00000000 \
  --allow-file-access-from-files --window-size="$w,$h" \
  --screenshot="$abs_out" "file://$abs_in" >/dev/null 2>&1

python3 - "$abs_out" "$w" "$h" "$opaque" <<'PY'
import struct, sys
path, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
if sys.argv[4] == '--opaque':
    from PIL import Image
    Image.open(path).convert('RGB').save(path, optimize=True)
with open(path, 'rb') as f:
    head = f.read(24)
aw, ah = struct.unpack('>II', head[16:24])
if (aw, ah) != (w, h):
    sys.exit(f'{path}: rendered {aw}x{ah}, expected {w}x{h}')
print(f'{path} {w}x{h}')
PY
