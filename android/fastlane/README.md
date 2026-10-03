# Google Play configuration

Store configuration for `com.mazino2d.simsplit`. Everything the Play Developer
API supports is managed from this repo; the rest is set by hand in Play Console
and recorded below so it can be re-entered or audited.

## Managed from the repo (GitOps)

| What | Source | Applied by |
| --- | --- | --- |
| Listing text (`en-US`, `vi` — folder names must be Play language codes, e.g. `vi` not `vi-VN`) | `metadata/android/<lang>/{title,short_description,full_description}.txt` | `play_metadata.yml` on push to `main` |
| Icon, feature graphic | `metadata/android/<lang>/images/{icon,featureGraphic}.png` | `play_metadata.yml` |
| Phone / 7" / 10" screenshots | `metadata/android/<lang>/images/{phone,sevenInch,tenInch}Screenshots/` | `play_metadata.yml` |
| Default language, contact email, website | `metadata/android/play.json` | `play_metadata.yml` |
| Data safety form | `metadata/android/data_safety.csv` (export from Play Console) | `play_metadata.yml` when the CSV changes |
| App bundles, tracks, release notes | `build_android.yml`, `release.yml` | manual dispatch / `vX.Y.Z` tag |

- PRs touching `metadata/` run `scripts/play_metadata.py check` (text limits,
  image sizes, 2–8 screenshots per type, max 2:1 aspect ratio).
- Syncing on push is **off** until the repo variable `PLAY_METADATA_AUTO_SYNC`
  is set to `true` (Settings → Secrets and variables → Actions → Variables).
  Until then, run the workflow manually.
- Preview a sync without changing Play: Actions → **Play Store Metadata** → Run
  workflow with `dry_run` checked (the default).
- Only images present in the repo are synced; an image type with no files here
  is left untouched on Play. Pushing the listing replaces what was edited by
  hand in Play Console for the same fields.
- Credentials: keyless Workload Identity Federation as
  `gha-play-publisher@mazino2d-as-se1-dev.iam.gserviceaccount.com`
  (see `mazino2d/everything-as-code`).

## Play Console access for CI

Granted by hand (the Play API supports it, but only community Terraform
providers exist and they need an admin-level JSON key):
Play Console → **Users and permissions** → `gha-play-publisher@…` →
**App permissions** → **SimSplit**.

| Section | Permission | Why |
| --- | --- | --- |
| Releases | Release to production, exclude devices, and use Play App Signing | `release.yml` |
| Releases | Release apps to testing tracks | `build_android.yml` |
| Releases | Manage testing tracks and edit tester lists | testing tracks |
| Store presence | Manage store presence | `play_metadata.yml` |

Leave everything else unticked, in particular **Edit and delete draft apps**
(lets the account delete an unpublished app; not needed for uploads or
listing sync) and any account-level/admin permission.

## Set by hand in Play Console (no API)

Policy and programs → **App content**:

| Declaration | Answer |
| --- | --- |
| Privacy policy | `https://mazino2d.github.io/sim-split/privacy-policy.html` |
| Ads | No ads |
| App access | All functionality available without special access |
| Content rating (IARC) | Category "All other app types", "No" to every question |
| Target audience | 18 and over |
| Advertising ID | Not used |
| Financial features | My app doesn't provide any financial features |
| Government apps, News, Health | No / not applicable |

Grow users → Store presence → **Store settings**: category **Finance**.

Update this table whenever a declaration changes in Play Console.
