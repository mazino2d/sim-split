---
name: uiux-designer
description: Design SimSplit's brand assets — the launcher icon (iOS, Android adaptive and themed), the splash logo, and Play Store graphics (hi-res icon, feature graphic, framed screenshots in EN and VI). Works from hand-written SVG masters in design/, renders 2–3 variants on a review sheet for the user to pick, then exports PNGs and regenerates platform icons. Use when the user asks to design, redesign or update the app icon, splash, feature graphic, store screenshots or "brand assets", or invokes /uiux-designer.
argument-hint: "[icon|splash|feature-graphic|screenshots] <brief>"
allowed-tools: Read, Write, Edit, Glob, Grep, AskUserQuestion, Bash(.claude/skills/uiux-designer/scripts/*), Bash(python3 .claude/skills/uiux-designer/scripts/*), Bash(dart run flutter_launcher_icons*), Bash(dart run flutter_native_splash*), Bash(python3 design/build.py*), Bash(flutter test*), Bash(flutter analyze*), Bash(git status*), Bash(git diff*)
---

# Design SimSplit assets

Every asset is a **monochrome** expression of the in-app design system: ink
`#0A0A0A` / white, greys, Be Vietnam Pro, generous radii. The green "owed"
accent is reserved for the app UI and is not used in brand assets unless the
user asks. Exact sizes, safe zones and tokens are in
[references/specs.md](references/specs.md) — read it before drawing.

## Principles

1. **One idea, one glyph.** The icon should say "split, settled" in a single
   shape — no text, no detail that dies at 48 px.
2. **Calm.** Flat fills, no gradients, no drop shadows baked into art, no
   noise. Matches the "Calm" principle in `docs/product/principles.md`.
3. **Same mark everywhere.** Launcher icon, splash, Play icon and feature
   graphic share one master glyph; only the framing changes.
4. **Both themes.** Every asset is checked on light and dark wallpaper.
5. **Source of truth is SVG.** Never hand-edit exported PNGs; edit the SVG
   and re-export.

## Workflow

### 1. Brief

Read `docs/product/strategy.md` (persona, positioning) and the current assets
(`assets/icons/`, `assets/images/`, `android/fastlane/metadata/android/*/images/`).
Then ask the user, with AskUserQuestion, only what the request leaves open,
for example:

- Which assets are in scope this time.
- The concept direction — offer 2–3 metaphors with a one-line trade-off each
  (e.g. split receipt: literal and recognisable but busy; two halves of a
  circle: abstract and bold but less obvious; ÷ mark: clear "split" but
  generic among calculator apps).
- For store graphics: the tagline (EN + VI) and which screens to feature.

### 2. Draw variants

Write 2–3 SVG variants to `design/<asset>/variants/<asset>-<letter>.svg`
(1024×1024 for icons, 1024×500 for the feature graphic). Hand-write clean
SVG: integer coordinates on a 1024 grid, `fill` with token colours, shapes
and paths only.

- Icons: no `<text>`. Any lettering must be converted to paths.
- Graphics with text: load the font with
  `@font-face{font-family:BVP;src:url("file:///<repo>/assets/fonts/BeVietnamPro-Bold.ttf")}`
  and render the SVG **directly** (fonts do not load when an SVG is embedded
  as `<img>`).

### 3. Review sheet

```bash
python3 .claude/skills/uiux-designer/scripts/contact_sheet.py \
  design/<asset>/review.png design/<asset>/variants/*.svg
```

Open `review.png` with Read and look at it critically before showing it:
safe zone respected in the circle mask, readable at 48 px, works on dark
wallpaper. Fix weak variants first. Then show the sheet and ask the user to
pick, describing each variant's trade-off in one line. Iterate until they
choose; do not export unchosen work.

For the feature graphic or screenshots, render each variant with
`render.sh` at its real size instead of the contact sheet.

### 4. Promote and export

Move the chosen master to `design/<asset>/<asset>.svg` (delete the other
variants unless the user wants them kept) and derive siblings from it — e.g.
the adaptive foreground and monochrome layers are the icon glyph without the
background, scaled into the 61% safe zone.

Then regenerate every output from the sources with **one command**:

```bash
python3 design/build.py                  # capture screens + all outputs
python3 design/build.py --skip-capture   # reuse captures (icon/caption-only changes)
python3 design/build.py --only icons     # or store | appstore | landing
```

`design/build.py` is the single pipeline. Its sources are `design/icon/*.svg`,
`design/store/feature_graphic.<lang>.svg`, `design/store/capture_test.dart`
(sample data + screens) and `design/shots.json` (shot list + EN/VI captions).
It writes:

- app icons and splash (`assets/`, then `flutter_launcher_icons` and
  `flutter_native_splash` for Android, iOS and web),
- Play icon, feature graphic and phone / 7" / 10" screenshots
  (`android/fastlane/metadata/android/<lang>/images/`),
- App Store iPhone 6.9" and iPad 13" screenshots (`ios/fastlane/screenshots/<lang>/`),
- the landing page icon and screens (`docs/assets/`).

To add or change a screenshot: add the screen to `capture_test.dart` (its
capture name is the shot id) and the shot to `shots.json`. Never edit an
output by hand. For a one-off render use
`.claude/skills/uiux-designer/scripts/render.sh <in> <out> <w> <h> [--opaque]`.

### 5. Verify

- Read every exported PNG once to confirm it rendered correctly (fonts,
  transparency, no cropping).
- `git status` — the diff should contain the SVG masters, exported PNGs,
  generated platform icon files and `pubspec.yaml` changes only.
- Run `flutter analyze --fatal-infos` if `pubspec.yaml` changed.
- If the store listing changed, remind the user that `play_metadata` syncs it
  on merge to `main`.
- If the landing page assets changed (`docs/assets/`), they go live on GitHub
  Pages on merge — check `docs/index.html` still references them.

Summarise for the user: what was chosen, files changed, and anything to check
on a real device (themed icon on Android 13+, splash on Android 12+).
