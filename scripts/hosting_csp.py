#!/usr/bin/env python3
"""Adds a Content-Security-Policy header for the built web app to firebase.json
(R-8 P4). Run after `flutter build web`, before `firebase deploy`, in CI only:
it edits firebase.json in place on the runner.

The policy allows what SimSplit loads: its own files (Flutter, the Drift worker
and sqlite3.wasm), Firebase and Google sign-in, reCAPTCHA Enterprise for App
Check, Google Fonts, the environment's telemetry endpoint, and Firebase Cloud
Messaging for web push (R-9: the service worker loads the SDK from gstatic and
registers through fcmregistrations and firebaseinstallations). Inline scripts
in index.html are allowed by hash, so no 'unsafe-inline' is needed for them.
The Firebase JS SDK is loaded by web/firebase_sdk.js (a file of our own, so
'self'), which stops FlutterFire from injecting an inline script per service.

  scripts/hosting_csp.py --telemetry-url URL --project ID [--report-only]

--report-only sends Content-Security-Policy-Report-Only: browsers only log
what the policy would block, which the smoke test turns into a failure.
"""

import argparse
import base64
import hashlib
import json
import pathlib
import re
import sys
from urllib.parse import urlparse

ROOT = pathlib.Path(__file__).resolve().parent.parent


def inline_script_hashes(index_html: str) -> list[str]:
    hashes = []
    for body in re.findall(r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", index_html, re.S):
        digest = hashlib.sha256(body.encode()).digest()
        hashes.append(f"'sha256-{base64.b64encode(digest).decode()}'")
    return hashes


def policy(telemetry_origin: str | None, project: str, hashes: list[str]) -> str:
    google = ["https://www.gstatic.com", "https://apis.google.com", "https://www.google.com", "https://accounts.google.com"]
    directives = {
        "default-src": ["'self'"],
        "script-src": ["'self'", "'wasm-unsafe-eval'", *hashes, *google],
        "style-src": ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
        "font-src": ["'self'", "data:", "https://fonts.gstatic.com"],
        "img-src": ["'self'", "data:", "blob:", "https://*.googleusercontent.com", "https://www.gstatic.com"],
        "connect-src": [
            "'self'",
            "https://*.googleapis.com",
            # R-9 web push. Covered by the wildcard above, named so that
            # narrowing it later keeps push working.
            "https://fcmregistrations.googleapis.com",
            "https://firebaseinstallations.googleapis.com",
            "https://www.google.com",
            "https://www.gstatic.com",
            "https://fonts.gstatic.com",
            *([telemetry_origin] if telemetry_origin else []),
        ],
        "frame-src": ["'self'", "https://www.google.com", "https://accounts.google.com", "https://apis.google.com", f"https://{project}.firebaseapp.com"],
        "worker-src": ["'self'", "blob:"],
        "object-src": ["'none'"],
        "base-uri": ["'self'"],
        "form-action": ["'self'"],
        "frame-ancestors": ["'self'"],
    }
    return "; ".join(f"{name} {' '.join(values)}" for name, values in directives.items())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--telemetry-url", default="")
    parser.add_argument("--project", required=True)
    parser.add_argument("--report-only", action="store_true")
    parser.add_argument("--web-dir", default=str(ROOT / "build/web"))
    parser.add_argument("--firebase-json", default=str(ROOT / "firebase.json"))
    args = parser.parse_args()

    index = pathlib.Path(args.web_dir, "index.html").read_text()
    url = urlparse(args.telemetry_url) if args.telemetry_url else None
    origin = f"{url.scheme}://{url.netloc}" if url and url.netloc else None
    value = policy(origin, args.project, inline_script_hashes(index))
    name = "Content-Security-Policy-Report-Only" if args.report_only else "Content-Security-Policy"

    config_path = pathlib.Path(args.firebase_json)
    config = json.loads(config_path.read_text())
    headers = config["hosting"].setdefault("headers", [])
    entry = next((h for h in headers if h.get("source") == "**"), None)
    if entry is None:
        entry = {"source": "**", "headers": []}
        headers.append(entry)
    entry["headers"] = [h for h in entry["headers"] if not h["key"].startswith("Content-Security-Policy")]
    entry["headers"].append({"key": name, "value": value})
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    print(f"{name}: {value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
