// R-9: shows push notifications while the web app is closed or in the
// background, and opens the message's link when one is tapped.
//
// The Firebase config comes from Firebase Hosting's reserved URL
// /__/firebase/init.js, which serves the config of the project the site
// belongs to, so the dev site gets dev's and the production site
// production's. The SDK version matches the one FlutterFire's
// firebase_core_web loads (supportedFirebaseJsSdkVersion); bump both
// together. Without Hosting (flutter run) init.js is missing and push stays
// off, which is fine: the app registers only with a FCM_VAPID_KEY build.
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-messaging-compat.js');
importScripts('/__/firebase/init.js');

// Notification messages are displayed by the SDK; the app itself shows
// nothing extra.
firebase.messaging();
