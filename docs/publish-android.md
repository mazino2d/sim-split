# Publishing SimSplit to Google Play Store

Package name: `com.mazino2d.simsplit`

---

## Prerequisites

- Google account with access to [Google Play Console](https://play.google.com/console)
- JDK 17+ installed locally
- Flutter 3.41.x installed
- `keytool` available (bundled with JDK)

---

## Step 1 — Create the app on Play Console (first time only)

1. Go to **Play Console → Create app**
2. Fill in:
   - **App name:** SimSplit
   - **Default language:** English (or Vietnamese)
   - **App or game:** App
   - **Free or paid:** Free
3. Accept the declarations and click **Create app**
4. Note the **package name** field — it must match `com.mazino2d.simsplit` exactly and cannot be changed later

---

## Step 2 — Create a signing keystore (first time only)

A keystore is required to sign release builds. **Never lose this file — it cannot be recovered.**

```bash
keytool -genkey -v \
  -keystore android/app/simsplit.jks \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -alias simsplit
```

You will be prompted for passwords and identity info. Store all values securely (e.g., a password manager).

Then create `android/key.properties` (already in `.gitignore`):

```properties
storePassword=<your_store_password>
keyPassword=<your_key_password>
keyAlias=simsplit
storeFile=simsplit.jks
```

> `android/app/build.gradle.kts` already reads this file automatically.

---

## Step 3 — Build the release AAB locally

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

---

## Step 4 — Upload to Play Console manually (first upload)

The very first upload **must be done manually** through the Play Console UI because the GitHub Actions workflow requires the app to already exist on the store.

1. Go to **Testing → Internal testing → Create new release**
2. Upload `app-release.aab`
3. Fill in release notes
4. Click **Review release → Start rollout to Internal testing**

After this first manual upload, all subsequent releases can be automated via CI.

---

## Step 5 — Set up GitHub Secrets for CI

Go to your GitHub repo → **Settings → Secrets and variables → Actions** and add:

| Secret name | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded keystore: `base64 -i android/app/simsplit.jks \| pbcopy` |
| `ANDROID_STORE_PASSWORD` | Store password from `key.properties` |
| `ANDROID_KEY_PASSWORD` | Key password from `key.properties` |
| `ANDROID_KEY_ALIAS` | `simsplit` |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | JSON key from Service Account (see Step 6) |

---

## Step 6 — Create a Google Play Service Account (for CI)

This allows GitHub Actions to upload builds automatically.

1. Go to [Google Cloud Console](https://console.cloud.google.com) → Create or select a project
2. Enable the **Google Play Android Developer API**
3. Go to **IAM & Admin → Service Accounts → Create Service Account**
   - Name: `simsplit-ci`
   - Role: no role needed at this level
4. Click the service account → **Keys → Add Key → Create new key → JSON**
5. Download the JSON file
6. Go to **Play Console → Home → Users and permissions** → find the service account → **App permissions** → add SimSplit → tick **Release apps to testing tracks** and **Release to production, exclude devices, and use Play App Signing**
7. Link to the Google Cloud project from step 1
8. Find the service account and click **Grant access** — this redirects to **Users and permissions**
   - Under **App permissions**, add SimSplit and grant at minimum **Releases: Release to testing tracks**
9. Paste the entire JSON file content as the `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` GitHub secret

---

## Step 7 — Automated CI releases

After the first manual upload and secrets are configured:

**Push to `main`** triggers `build_android.yml` automatically and uploads to the **internal** track.

**Manual trigger** with track selection:

```
GitHub → Actions → Build Android → Run workflow → select track
```

Available tracks: `internal` → `alpha` → `beta` → `production`

**Promote from internal to production** using Fastlane:

```bash
cd android
bundle exec fastlane production
```

---

## Step 8 — Complete store listing (before going public)

In Play Console → **Store presence**:

- [ ] App icon (512×512 PNG, no alpha)
- [ ] Feature graphic (1024×500 PNG)
- [ ] Screenshots — at least 2 phone screenshots
- [ ] Short description (80 chars max)
- [ ] Full description
- [ ] Category: Finance

Store assets are in [`store_assets/android/`](../store_assets/android/).

---

## Troubleshooting

**`keystore not found` during build**
Make sure `android/key.properties` exists and `storeFile` path is relative to `android/app/`.

**`Google Play: Package not found`**
The app must be uploaded manually at least once before the API can reference it.

**`Version code already exists`**
`versionCode` in `pubspec.yaml` must be incremented before each upload.

**Service account `401 Unauthorized`**
Re-check that the service account is linked in Play Console → API access and has **Release manager** permission.
