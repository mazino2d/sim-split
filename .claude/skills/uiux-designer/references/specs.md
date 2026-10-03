# Asset specs

Sizes and safe zones for every asset this skill produces. All masters are SVG
in `design/`; PNGs are exports.

## Launcher icon

| Output | Size | Notes |
| --- | --- | --- |
| `assets/icons/app_icon.png` | 1024×1024 | Full icon (background + glyph). Used for iOS and legacy Android. **iOS rejects transparency**: fill every pixel. |
| `assets/icons/app_icon_foreground.png` | 1024×1024 | Android adaptive foreground, transparent background. The layer is 108 dp; launchers show the centre 72 dp and any mask shape is guaranteed only within the centre **66 dp circle (61% → 626 px diameter)**. Draw the master with that padding already in place and set `adaptive_icon_foreground_inset: 0` — the tool's default inset of 16% would shrink the glyph a second time. |
| `assets/icons/app_icon_monochrome.png` | 1024×1024 | Android 13+ themed icon. Single colour (white) on transparent, same safe zone as the foreground. The system tints it. |
| `adaptive_icon_background` | colour | Solid colour in `pubspec.yaml` (`flutter_launcher_icons`). Keep it a token from `AppTheme`. |
| `android/fastlane/metadata/android/{en-US,vi}/images/icon.png` | 512×512 | Play Store hi-res icon. 32-bit PNG, full bleed (Play applies the mask and shadow). Same art as `app_icon.png`. |

`flutter_launcher_icons` config keys: `image_path`, `adaptive_icon_background`,
`adaptive_icon_foreground`, `adaptive_icon_foreground_inset: 0`,
`adaptive_icon_monochrome`, `remove_alpha_ios: true`.
Regenerate with `dart run flutter_launcher_icons`.

### Legibility

- One idea, one glyph. No text, no thin hairlines: strokes ≥ 6% of the canvas
  (≥ 60 px at 1024) so they survive at 48 px.
- Check the contact sheet at 48 px on both light and dark wallpaper before
  proposing a variant.

## Splash

| Output | Size | Notes |
| --- | --- | --- |
| `assets/images/splash_logo.png` | 1152×1152 | Android 12+ splash icon: the system shows it inside a circle of 2/3 the canvas (768 px). Keep the glyph within that circle, transparent background. |
| `assets/images/splash_logo_dark.png` (optional) | 1152×1152 | Use when the light logo disappears on the dark splash colour. |

`flutter_native_splash` keys: `color`, `color_dark`, `image`, `image_dark`,
`android_12.{image,image_dark,color,color_dark,icon_background_color,icon_background_color_dark}`.
Splash colours must match `AppTheme` surfaces (`#FFFFFF` / `#0B0B0B`).
Regenerate with `dart run flutter_native_splash:create`.

## Play Store graphics

Listings exist for `en-US` and `vi` under `android/fastlane/metadata/android/`;
produce every graphic for **both** languages.

| Output | Size | Notes |
| --- | --- | --- |
| `images/featureGraphic.png` | 1024×500 | No alpha. Keep key content within the centre ~ 924×400; Play may overlay a play button in the middle when a promo video exists. Text short and large (≥ 48 px). |
| `images/phoneScreenshots/NN_name.png` | 1080×1920 or 1080×2340 | 2–8 shots, 9:16 to 9:21. Framed shot = app capture + caption, caption ≤ 6 words, localised. |
| `images/sevenInchScreenshots/`, `images/tenInchScreenshots/` | tablet | Optional; reuse phone captures centred on a larger canvas. |

## App Store screenshots

Locales `en-US` and `vi` under `ios/fastlane/screenshots/`; `deliver`
detects the device from the image size.

| Output | Size | Notes |
| --- | --- | --- |
| `<lang>/NN_name_iphone69.png` | 1320×2868 | iPhone 6.9"; required. No alpha. |
| `<lang>/NN_name_ipad13.png` | 2064×2752 | iPad 13"; required because the app supports iPad. No alpha. |

Raw app captures come from `design/store/capture_test.dart` (realistic
sample data, EN and VI); `design/build.py` frames them for every target.

## Design tokens (from `lib/presentation/theme/app_theme.dart`)

| Token | Light | Dark |
| --- | --- | --- |
| Ink / primary | `#0A0A0A` | `#F5F5F5` |
| Surface | `#FFFFFF` | `#0B0B0B` |
| Surface container | `#F2F2F2` | `#1A1A1A` |
| Muted text | `#6B6B6B` | `#A3A3A3` |
| Outline | `#CFCFCF` | `#3D3D3D` |
| Owed (accent, use sparingly) | `#067647` | `#47CD89` |
| Owe | `#C4320A` | `#F97066` |

Typeface: Be Vietnam Pro (`assets/fonts/`, weights 400–700). Corner radii
12 / 16 / 24.
