#!/usr/bin/env python3
"""Sync the Google Play store listing from android/fastlane/metadata/android.

Usage:
  play_metadata.py check                  Validate metadata offline (stdlib only).
  play_metadata.py sync [--dry-run]       Push listings, images and contact details.
                        [--data-safety]   Also upload data_safety.csv.

`sync` needs google-api-python-client and Application Default Credentials for an
account invited in Play Console with "Manage store presence" (in CI:
google-github-actions/auth via Workload Identity Federation).

Layout (fastlane-compatible):
  play.json                                package name, default language, contact
  data_safety.csv                          optional, exported from Play Console
  <lang>/title.txt                         max 30 chars
  <lang>/short_description.txt             max 80 chars
  <lang>/full_description.txt              max 4000 chars
  <lang>/images/icon.png                   512x512
  <lang>/images/featureGraphic.png         1024x500
  <lang>/images/{phone,sevenInch,tenInch}Screenshots/*.png|jpg   2-8 each
"""

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "android/fastlane/metadata/android"

TEXT_LIMITS = {"title.txt": 30, "short_description.txt": 80, "full_description.txt": 4000}
LISTING_FIELDS = {
    "title.txt": "title",
    "short_description.txt": "shortDescription",
    "full_description.txt": "fullDescription",
}
SINGLE_IMAGES = {"icon": (512, 512), "featureGraphic": (1024, 500)}
SCREENSHOT_TYPES = ("phoneScreenshots", "sevenInchScreenshots", "tenInchScreenshots")
IMAGE_TYPES = tuple(SINGLE_IMAGES) + SCREENSHOT_TYPES


# ── Local metadata ──────────────────────────────────────────────────────────


def image_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:2] == b"\xff\xd8":  # JPEG: scan for a start-of-frame marker
        i = 2
        while i < len(data):
            marker, length = data[i + 1], struct.unpack(">H", data[i + 2 : i + 4])[0]
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                h, w = struct.unpack(">HH", data[i + 5 : i + 9])
                return w, h
            i += 2 + length
    raise ValueError(f"{path}: not a PNG or JPEG")


def languages() -> list[str]:
    return sorted(p.name for p in ROOT.iterdir() if p.is_dir())


def images_for(lang: str, image_type: str) -> list[Path]:
    images = ROOT / lang / "images"
    if image_type in SINGLE_IMAGES:
        found = [p for ext in ("png", "jpg", "jpeg") if (p := images / f"{image_type}.{ext}").exists()]
        return found[:1]
    folder = images / image_type
    if not folder.is_dir():
        return []
    return sorted(p for p in folder.iterdir() if p.suffix.lower() in (".png", ".jpg", ".jpeg"))


def check() -> list[str]:
    errors = []
    config = json.loads((ROOT / "play.json").read_text())
    for key in ("packageName", "defaultLanguage", "contactEmail"):
        if not config.get(key):
            errors.append(f"play.json: missing {key}")
    if config.get("defaultLanguage") not in languages():
        errors.append(f"play.json: defaultLanguage {config.get('defaultLanguage')} has no folder")

    for lang in languages():
        for name, limit in TEXT_LIMITS.items():
            path = ROOT / lang / name
            if not path.exists():
                errors.append(f"{lang}/{name}: missing")
                continue
            text = path.read_text().strip()
            if not text:
                errors.append(f"{lang}/{name}: empty")
            elif len(text) > limit:
                errors.append(f"{lang}/{name}: {len(text)} chars, max {limit}")

        for image_type, expected in SINGLE_IMAGES.items():
            for path in images_for(lang, image_type):
                if image_size(path) != expected:
                    errors.append(f"{path.relative_to(ROOT)}: {image_size(path)}, expected {expected}")

        for image_type in SCREENSHOT_TYPES:
            shots = images_for(lang, image_type)
            if shots and not 2 <= len(shots) <= 8:
                errors.append(f"{lang}/images/{image_type}: {len(shots)} files, need 2-8")
            for path in shots:
                w, h = image_size(path)
                if not (320 <= min(w, h) and max(w, h) <= 3840 and max(w, h) <= 2 * min(w, h)):
                    errors.append(
                        f"{path.relative_to(ROOT)}: {w}x{h}; sides must be 320-3840 px "
                        "and the long side at most 2x the short side"
                    )
    return errors


# ── Play Developer API ──────────────────────────────────────────────────────


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sync(dry_run: bool, data_safety: bool) -> None:
    import google.auth
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload

    config = json.loads((ROOT / "play.json").read_text())
    package = config["packageName"]
    credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/androidpublisher"])
    api = build("androidpublisher", "v3", credentials=credentials, cache_discovery=False)
    edits = api.edits()
    edit_id = edits.insert(packageName=package, body={}).execute()["id"]
    ids = {"packageName": package, "editId": edit_id}
    changes = []

    try:
        details = edits.details().get(**ids).execute()
        wanted = {
            "defaultLanguage": config["defaultLanguage"],
            "contactEmail": config["contactEmail"],
            "contactWebsite": config.get("contactWebsite", ""),
        }
        if any(details.get(k, "") != v for k, v in wanted.items()):
            changes.append("details")
            if not dry_run:
                edits.details().patch(**ids, body=wanted).execute()

        remote_listings = {
            l["language"]: l for l in edits.listings().list(**ids).execute().get("listings", [])
        }
        for lang in languages():
            wanted = {
                field: (ROOT / lang / name).read_text().strip()
                for name, field in LISTING_FIELDS.items()
            }
            current = remote_listings.get(lang, {})
            if any(current.get(k, "") != v for k, v in wanted.items()):
                changes.append(f"{lang} listing")
                if not dry_run:
                    edits.listings().update(**ids, language=lang, body=wanted).execute()

            for image_type in IMAGE_TYPES:
                local = images_for(lang, image_type)
                if not local:
                    continue  # not managed in the repo; leave Play's copy untouched
                remote = edits.images().list(**ids, language=lang, imageType=image_type).execute()
                remote_hashes = [i.get("sha256") for i in remote.get("images", [])]
                if remote_hashes == [sha256(p) for p in local]:
                    continue
                changes.append(f"{lang} {image_type} ({len(local)})")
                if dry_run:
                    continue
                edits.images().deleteall(**ids, language=lang, imageType=image_type).execute()
                for path in local:
                    mime = "image/png" if path.suffix.lower() == ".png" else "image/jpeg"
                    edits.images().upload(
                        **ids, language=lang, imageType=image_type,
                        media_body=MediaFileUpload(str(path), mimetype=mime),
                    ).execute()

        if not changes or dry_run:
            edits.delete(**ids).execute()
        else:
            edits.commit(**ids).execute()
    except Exception:
        edits.delete(**ids).execute()
        raise

    verb = "Would change" if dry_run else "Changed"
    print(f"{verb}: {', '.join(changes)}" if changes else "Store listing already up to date.")

    csv = ROOT / "data_safety.csv"
    if data_safety and csv.exists():
        if dry_run:
            print("Would upload data_safety.csv")
        else:
            api.applications().dataSafety(
                packageName=package, body={"safetyLabels": csv.read_text()}
            ).execute()
            print("Uploaded data_safety.csv")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check")
    sync_parser = sub.add_parser("sync")
    sync_parser.add_argument("--dry-run", action="store_true")
    sync_parser.add_argument("--data-safety", action="store_true")
    args = parser.parse_args()

    errors = check()
    for error in errors:
        print(f"::error::{error}")
    if errors:
        sys.exit(1)
    if args.command == "check":
        print(f"Store metadata OK ({', '.join(languages())}).")
        return
    sync(args.dry_run, args.data_safety)


if __name__ == "__main__":
    main()
