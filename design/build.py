#!/usr/bin/env python3
"""Regenerate every brand and store image from the sources in design/.

Sources (edit these):
  design/icon/*.svg                 app mark, adaptive/themed layers, splash
  design/store/feature_graphic.*.svg Play feature graphic per locale
  design/store/capture_test.dart    sample data and the app screens to capture
  design/shots.json                 which captures become screenshots + captions

Outputs (never edit by hand):
  assets/icons, assets/images       -> flutter_launcher_icons / native_splash
                                       -> Android, iOS and web app icons, splash
  android/fastlane/metadata/...     Play icon, feature graphic, phone/7"/10" shots
  ios/fastlane/screenshots/...      App Store iPhone 6.9" and iPad 13" shots
  docs/assets/...                   landing page icon and app screens

Usage:
  python3 design/build.py                 # everything
  python3 design/build.py --skip-capture  # reuse existing captures
  python3 design/build.py --only icons|store|appstore|landing
"""
import argparse
import html
import json
import pathlib
import shutil
import subprocess
import tempfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
DESIGN = ROOT / "design"
RENDER = ROOT / ".claude/skills/uiux-designer/scripts/render.sh"
CAPTURES = DESIGN / "store/captures"
PLAY = ROOT / "android/fastlane/metadata/android"
APPSTORE = ROOT / "ios/fastlane/screenshots"
DOCS = ROOT / "docs/assets"
FONT = ROOT / "assets/fonts/BeVietnamPro-Bold.ttf"

# Store folder -> capture locale. Play uses en-US / vi; App Store uses en-US / vi.
LOCALES = {"en-US": "en", "vi": "vi"}

PLAY_SIZES = {
    "phoneScreenshots": (1080, 1920),
    "sevenInchScreenshots": (1080, 1920),
    "tenInchScreenshots": (1620, 2880),
}
APPSTORE_SIZES = {  # file suffix -> size; deliver detects the device from the size
    "iphone69": (1320, 2868),
    "ipad13": (2064, 2752),
}
CAPTURE_W, CAPTURE_H = 1080, 1800

TMP = pathlib.Path(tempfile.mkdtemp())


def run(*cmd: str) -> None:
    subprocess.run(cmd, cwd=ROOT, check=True)


def render(src: pathlib.Path, out: pathlib.Path, w: int, h: int, opaque: bool = False) -> None:
    args = [str(RENDER), str(src), str(out), str(w), str(h)]
    if opaque:
        args.append("--opaque")
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)
    print(f"  {out.relative_to(ROOT)}  {w}x{h}")


# ── Captures ────────────────────────────────────────────────────────────────

def capture() -> None:
    print("Capturing app screens")
    run("flutter", "test", "design/store/capture_test.dart", "--update-goldens")


# ── Icons ───────────────────────────────────────────────────────────────────

def icons() -> None:
    print("Icons and splash")
    icon = DESIGN / "icon"
    render(icon / "icon.svg", ROOT / "assets/icons/app_icon.png", 1024, 1024, opaque=True)
    render(icon / "icon_foreground.svg", ROOT / "assets/icons/app_icon_foreground.png", 1024, 1024)
    render(icon / "icon_monochrome.svg", ROOT / "assets/icons/app_icon_monochrome.png", 1024, 1024)
    render(icon / "splash_light.svg", ROOT / "assets/images/splash_logo.png", 1152, 1152)
    render(icon / "splash_dark.svg", ROOT / "assets/images/splash_logo_dark.png", 1152, 1152)
    for folder in LOCALES:
        render(icon / "icon.svg", PLAY / folder / "images/icon.png", 512, 512, opaque=True)
    render(icon / "icon.svg", DOCS / "icon.png", 512, 512, opaque=True)
    run("dart", "run", "flutter_launcher_icons")
    run("dart", "run", "flutter_native_splash:create")


# ── Framed screenshots ──────────────────────────────────────────────────────

def frame_page(capture_png: pathlib.Path, caption: str, dark: bool, w: int, h: int) -> str:
    """Caption on top, the app screen below, scaled to fit any canvas."""
    bg, ink, edge = ("#0B0B0B", "#F5F5F5", "#2A2A2A") if dark else ("#F2F2F2", "#0A0A0A", "#E0E0E0")
    font = round(min(h * 0.033, w * 0.075))
    caption_h = round(font * 2 * 1.2 + h * 0.04)  # room for two lines + gap
    margin = round(h * 0.05)
    screen_h = h - caption_h - 2 * margin
    screen_w = round(screen_h * CAPTURE_W / CAPTURE_H)
    if screen_w > w * 0.86:
        screen_w = round(w * 0.86)
        screen_h = round(screen_w * CAPTURE_H / CAPTURE_W)
    start = (h - caption_h - screen_h) // 2  # centre caption + screen as one block
    radius = round(screen_w * 0.051)
    return f"""<!doctype html><html><head><style>
@font-face{{font-family:BVP;src:url("file://{FONT}")}}
html,body{{margin:0}}
body{{width:{w}px;height:{h}px;background:{bg};font-family:BVP;overflow:hidden;position:relative}}
h1{{margin:0;position:absolute;left:{round(w*0.08)}px;right:{round(w*0.08)}px;top:{start}px;
   height:{caption_h - round(h*0.04)}px;display:flex;align-items:center;justify-content:center;
   text-align:center;color:{ink};font-size:{font}px;line-height:1.2;letter-spacing:-1px;text-wrap:balance}}
.screen{{position:absolute;top:{start + caption_h}px;left:{(w-screen_w)//2}px;width:{screen_w}px;height:{screen_h}px;
   border-radius:{radius}px;overflow:hidden;box-shadow:0 0 0 2px {edge}}}
.screen img{{display:block;width:{screen_w}px}}
</style></head><body>
<h1>{html.escape(caption)}</h1>
<div class="screen"><img src="file://{capture_png}"></div>
</body></html>"""


def framed(out: pathlib.Path, shot: dict, locale: str, w: int, h: int) -> None:
    page = TMP / f"{out.parent.name}-{out.name}.html"
    page.write_text(frame_page(CAPTURES / locale / f"{shot['id']}.png", shot["caption"][locale], shot["dark"], w, h))
    render(page, out, w, h, opaque=True)


def shots() -> list:
    return json.loads((DESIGN / "shots.json").read_text())["shots"]


def store() -> None:
    print("Play Store")
    for folder, locale in LOCALES.items():
        images = PLAY / folder / "images"
        render(DESIGN / f"store/feature_graphic.{folder}.svg", images / "featureGraphic.png", 1024, 500, opaque=True)
        for kind, (w, h) in PLAY_SIZES.items():
            out_dir = images / kind
            if out_dir.exists():
                shutil.rmtree(out_dir)
            out_dir.mkdir(parents=True)
            for shot in shots():
                framed(out_dir / f"{shot['id']}.png", shot, locale, w, h)
    run("python3", "scripts/play_metadata.py", "check")


def appstore() -> None:
    print("App Store")
    for folder, locale in LOCALES.items():
        out_dir = APPSTORE / folder
        if out_dir.exists():
            shutil.rmtree(out_dir)
        out_dir.mkdir(parents=True)
        for device, (w, h) in APPSTORE_SIZES.items():
            for shot in shots():
                framed(out_dir / f"{shot['id']}_{device}.png", shot, locale, w, h)


def landing() -> None:
    print("Landing page")
    for locale in set(LOCALES.values()):
        out_dir = DOCS / "screens" / locale
        if out_dir.exists():
            shutil.rmtree(out_dir)
        out_dir.mkdir(parents=True)
        for shot in shots():
            if shot["dark"]:
                continue  # the page shows light screens; dark mode follows the visitor
            im = Image.open(CAPTURES / locale / f"{shot['id']}.png").convert("RGB")
            im = im.resize((540, round(im.height * 540 / im.width)), Image.LANCZOS)
            out = out_dir / f"{shot['id']}.webp"
            im.save(out, "WEBP", quality=88, method=6)
            print(f"  {out.relative_to(ROOT)}")


STEPS = {"icons": icons, "store": store, "appstore": appstore, "landing": landing}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--skip-capture", action="store_true", help="reuse design/store/captures")
    parser.add_argument("--only", choices=STEPS, help="run a single step")
    args = parser.parse_args()

    needs_captures = args.only in (None, "store", "appstore", "landing")
    if needs_captures and not args.skip_capture:
        capture()
    for name, step in STEPS.items():
        if args.only in (None, name):
            step()
    print("Done. Review the images, then commit sources and outputs together.")


if __name__ == "__main__":
    main()
