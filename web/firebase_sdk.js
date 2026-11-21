// Loads the Firebase JS SDK from a file of our own (R-8 P4, the
// Content-Security-Policy), then starts Flutter.
//
// FlutterFire otherwise injects one inline <script> per Firebase service at
// startup; inline scripts break a CSP without 'unsafe-inline', and their hashes
// change with every Firebase release. firebase_core_web skips that injection
// when window.firebase_core is already set, so this module sets the same
// globals it would (firebase_<service>), from the same gstatic URLs.
//
// FIREBASE_JS_SDK_VERSION must equal firebase_core_web's
// supportedFirebaseJsSdkVersion; test/unit/web/firebase_sdk_version_test.dart
// fails when a dependency update changes it (as does web/firebase-messaging-sw.js).
const FIREBASE_JS_SDK_VERSION = '13.1.0';

const base = `https://www.gstatic.com/firebasejs/${FIREBASE_JS_SDK_VERSION}`;

// The services the app's FlutterFire plugins register (window name → bundle).
// firebase-app.js loads first: the others import it, and parallel first
// imports of it trip a WebKit bug (flutterfire#18436).
const services = {
  firebase_auth: 'firebase-auth.js',
  firebase_app_check: 'firebase-app-check.js',
  firebase_firestore: 'firebase-firestore-pipelines.js',
  firebase_messaging: 'firebase-messaging.js',
};

// Belt and braces: never let FlutterFire inject a script, even if a global is missing.
window.flutterfire_ignore_scripts = ['core', 'auth', 'app_check', 'firestore', 'messaging'];

try {
  window.firebase_core = await import(`${base}/firebase-app.js`);
  const modules = await Promise.all(Object.values(services).map((file) => import(`${base}/${file}`)));
  Object.keys(services).forEach((name, i) => {
    window[name] = modules[i];
  });
} catch (error) {
  // Offline on a cold start, or gstatic blocked: Flutter still starts and
  // Firebase.initializeApp reports the failure as it would have anyway.
  console.warn('Firebase JS SDK did not load', error);
}

const bootstrap = document.createElement('script');
bootstrap.src = 'flutter_bootstrap.js';
bootstrap.async = true;
document.body.appendChild(bootstrap);
