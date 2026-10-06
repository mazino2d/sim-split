# Security Policy

SimSplit signs users in with Google (Firebase Auth) and syncs shared groups
through Cloud Firestore; a local database on the device keeps the app working
offline. Firestore security rules decide who can read and change each group, so
the main risks are:

- the rules in [`firebase/firestore.rules`](firebase/firestore.rules) — anyone
  reading or changing a group they are not a member of, or a member doing
  something the rules should forbid (changing who is in a group other than
  leaving it, editing or deleting activity history);
- invite links — joining a group without a valid invite;
- the app itself — data left on the device after sign-out, or leaked through
  logs;
- its dependencies, and the CI that builds and publishes it.

## Supported versions

Security fixes go to the latest release on Google Play and to the web app at
[simsplit.web.app](https://simsplit.web.app). Older Android versions are not
patched; please update.

## Reporting a vulnerability

Please report privately through
[GitHub private vulnerability reporting](https://github.com/mazino2d/sim-split/security/advisories/new).
Do not open a public issue.

Include what you found, how to reproduce it and the app version or platform. You
should get a reply within 7 days. Once a fix ships, the advisory is published
with credit to you unless you prefer otherwise.

Test only against your own account and groups, or against the Firestore
emulator (see [CONTRIBUTING.md](CONTRIBUTING.md)). Do not access other people's
data or degrade the service for others.
