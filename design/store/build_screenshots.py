#!/usr/bin/env python3
"""Frame raw captures into Play Store screenshots with localized captions.

Run capture_test.dart first (see its header), then:

    python3 design/store/build_screenshots.py

Writes phone and 7-inch shots at 1080x1920 and 10-inch shots at 1620x2880
into android/fastlane/metadata/android/<lang>/images/, replacing old ones.
"""
import html
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
CAPTURES = ROOT / "design/store/captures"
METADATA = ROOT / "android/fastlane/metadata/android"
RENDER = ROOT / ".claude/skills/design-assets/scripts/render.sh"
FONT = ROOT / "assets/fonts/BeVietnamPro-Bold.ttf"

# capture name -> (dark?, EN caption, VI caption)
SHOTS = {
    "01_home": (False, "Who owes whom, at a glance", "Ai nợ ai, nhìn là biết"),
    "02_add_expense": (False, "Log an expense in seconds", "Ghi một khoản trong vài giây"),
    "03_settle_up": (False, "Settle up in the fewest transfers", "Trả nợ với ít lần chuyển nhất"),
    "04_dark": (True, "Works offline. No sign-up.", "Không cần mạng, không cần tài khoản"),
}
LOCALES = {"en-US": ("en", 1), "vi": ("vi", 2)}  # Play folder -> (capture dir, caption index)
SIZES = {  # folder -> (width, height, zoom)
    "phoneScreenshots": (1080, 1920, 1.0),
    "sevenInchScreenshots": (1080, 1920, 1.0),
    "tenInchScreenshots": (1620, 2880, 1.5),
}


def page(capture: pathlib.Path, caption: str, dark: bool, zoom: float) -> str:
    bg, ink, edge = ("#0B0B0B", "#F5F5F5", "#2A2A2A") if dark else ("#F2F2F2", "#0A0A0A", "#E0E0E0")
    return f"""<!doctype html><html><head><style>
@font-face{{font-family:BVP;src:url("file://{FONT}")}}
html,body{{margin:0}}
body{{zoom:{zoom};width:1080px;height:1920px;background:{bg};font-family:BVP;overflow:hidden}}
h1{{margin:0;position:absolute;top:150px;left:90px;right:90px;text-align:center;
   color:{ink};font-size:64px;line-height:1.2;letter-spacing:-1px;text-wrap:balance}}
.screen{{position:absolute;top:420px;left:110px;width:860px;height:1433px;border-radius:44px;
   overflow:hidden;box-shadow:0 0 0 2px {edge}}}
.screen img{{display:block;width:860px}}
</style></head><body>
<h1>{html.escape(caption)}</h1>
<div class="screen"><img src="file://{capture}"></div>
</body></html>"""


def main() -> None:
    tmp = pathlib.Path(tempfile.mkdtemp())
    for folder, (cap_dir, idx) in LOCALES.items():
        for kind, (w, h, zoom) in SIZES.items():
            out_dir = METADATA / folder / "images" / kind
            out_dir.mkdir(parents=True, exist_ok=True)
            for old in out_dir.glob("*.png"):
                old.unlink()
            for name, shot in SHOTS.items():
                src = tmp / f"{folder}-{kind}-{name}.html"
                src.write_text(page(CAPTURES / cap_dir / f"{name}.png", shot[idx], shot[0], zoom))
                subprocess.run(
                    [str(RENDER), str(src), str(out_dir / f"{name}.png"), str(w), str(h), "--opaque"],
                    check=True,
                )


if __name__ == "__main__":
    main()
