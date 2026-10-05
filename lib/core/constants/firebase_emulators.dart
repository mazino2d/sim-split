/// Host of the local Firebase Auth and Firestore emulators, set with
/// `--dart-define=FIREBASE_EMULATOR_HOST=localhost`. Empty in real builds.
/// The web e2e journey runs against the emulators so it can sign in without
/// Google (see .claude/skills/e2e-tester/scripts/e2e_web.sh).
const firebaseEmulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');

/// Ports from `firebase.json`.
const firebaseAuthEmulatorPort = 9099;
const firestoreEmulatorPort = 8080;

/// The emulators run on a demo project, which never reaches real services.
const firebaseEmulatorProjectId = 'demo-simsplit';
