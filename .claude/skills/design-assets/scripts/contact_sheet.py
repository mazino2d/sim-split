#!/usr/bin/env python3
"""Build a review sheet comparing icon variants, then render it to PNG.

Each variant is a 1024x1024 SVG. The sheet shows every variant on light and
dark wallpaper, inside circle / squircle / rounded-square launcher masks, and
at 192, 96 and 48 px so legibility at small sizes is visible at a glance.

Usage: contact_sheet.py <out.png> <variant1.svg> [<variant2.svg> ...]
"""
import html
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
out = pathlib.Path(sys.argv[1]).resolve()
variants = [pathlib.Path(p).resolve() for p in sys.argv[2:]]
if not variants:
    sys.exit(__doc__)

MASKS = [("circle", "50%"), ("squircle", "30%"), ("square", "18%")]
SIZES = [192, 96, 48]
FONT = (HERE / "../../../../assets/fonts/BeVietnamPro-SemiBold.ttf").resolve()

rows = []
for v in variants:
    cells = []
    for bg, fg in (("#F2F2F2", "#0A0A0A"), ("#1A1A1A", "#F5F5F5")):
        tiles = "".join(
            f'<div class="t" style="width:{s}px;height:{s}px;border-radius:{r}">'
            f'<img src="file://{v}" width="{s}" height="{s}"></div>'
            for _, r in MASKS
            for s in SIZES[:1]
        ) + "".join(
            f'<div class="t" style="width:{s}px;height:{s}px;border-radius:30%">'
            f'<img src="file://{v}" width="{s}" height="{s}"></div>'
            for s in SIZES[1:]
        )
        cells.append(f'<div class="bg" style="background:{bg};color:{fg}">{tiles}</div>')
    rows.append(
        f'<div class="row"><div class="name">{html.escape(v.stem)}</div>{"".join(cells)}</div>'
    )

width = 1900
height = 60 + len(variants) * 300
page = out.with_suffix(".html")
page.write_text(f"""<!doctype html><html><head><style>
@font-face{{font-family:BVP;src:url("file://{FONT}")}}
body{{margin:0;background:#fff;font-family:BVP;width:{width}px}}
.row{{display:flex;align-items:center;gap:24px;padding:24px}}
.name{{width:160px;font-size:22px}}
.bg{{display:flex;align-items:center;gap:20px;padding:24px;border-radius:24px}}
.t{{overflow:hidden;flex:none;box-shadow:0 1px 3px rgba(0,0,0,.25)}}
.t img{{display:block}}
</style></head><body>{"".join(rows)}</body></html>""")
subprocess.run(
    [str(HERE / "render.sh"), str(page), str(out), str(width), str(height)],
    check=True,
)
