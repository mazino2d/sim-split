#!/usr/bin/env python3
"""Show or change the staged rollout of the current production release.

Usage:
  play_rollout.py status              Print the production track's releases.
  play_rollout.py set <fraction>      Widen the rollout, e.g. 0.5; 1 completes it.
  play_rollout.py halt                Stop the rollout (users who have it keep it).
  play_rollout.py resume              Restart a halted rollout at its last fraction.

Acts on the newest production release that is inProgress or halted. Needs
google-api-python-client and Application Default Credentials for the Play
publisher account (in CI: Workload Identity Federation, see play_rollout.yml).
"""

import argparse
import json
from pathlib import Path

PLAY_JSON = Path(__file__).resolve().parent.parent / "android/fastlane/metadata/android/play.json"
TRACK = "production"


def describe(release: dict) -> str:
    codes = ",".join(release.get("versionCodes", [])) or "-"
    fraction = release.get("userFraction")
    share = f" {fraction:.0%}" if fraction is not None else ""
    return f"{release.get('name', '?')} (versionCode {codes}): {release['status']}{share}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    set_parser = sub.add_parser("set")
    set_parser.add_argument("fraction", type=float)
    sub.add_parser("halt")
    sub.add_parser("resume")
    args = parser.parse_args()
    if args.command == "set" and not 0 < args.fraction <= 1:
        parser.error("fraction must be in (0, 1]")

    import google.auth
    from googleapiclient.discovery import build

    package = json.loads(PLAY_JSON.read_text())["packageName"]
    credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/androidpublisher"])
    edits = build("androidpublisher", "v3", credentials=credentials, cache_discovery=False).edits()
    edit_id = edits.insert(packageName=package, body={}).execute()["id"]
    ids = {"packageName": package, "editId": edit_id}
    try:
        track = edits.tracks().get(**ids, track=TRACK).execute()
        releases = track.get("releases", [])
        for release in releases:
            print(describe(release))
        if args.command == "status":
            return

        staged = [r for r in releases if r["status"] in ("inProgress", "halted")]
        if not staged:
            raise SystemExit("No staged production release to change.")
        release = staged[0]
        if args.command == "set":
            if args.fraction == 1:
                release["status"] = "completed"
                release.pop("userFraction", None)
            else:
                if args.fraction <= release.get("userFraction", 0):
                    raise SystemExit(f"Rollout is already at {release['userFraction']:.0%}; it can only grow.")
                release["status"] = "inProgress"
                release["userFraction"] = args.fraction
        elif args.command == "halt":
            release["status"] = "halted"
        elif args.command == "resume":
            release["status"] = "inProgress"

        edits.tracks().update(**ids, track=TRACK, body=track).execute()
        edits.commit(**ids).execute()
        edit_id = None
        print(f"Now: {describe(release)}")
    finally:
        if edit_id:
            edits.delete(**ids).execute()


if __name__ == "__main__":
    main()
