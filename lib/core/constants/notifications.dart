/// The public Web Push (VAPID) key of the build's Firebase project, set with
/// `--dart-define=FCM_VAPID_KEY=<key>` (R-9). Firebase console → Project
/// settings → Cloud Messaging → Web Push certificates; each environment has
/// its own. Empty means the web app does not register for push; Android
/// does not need it.
const fcmVapidKey = String.fromEnvironment('FCM_VAPID_KEY');

/// The Android MethodChannel that creates one notification channel per
/// category (`android/app/src/main/kotlin/.../MainActivity.kt`).
const notificationChannelsMethodChannel = 'simsplit/notifications';
