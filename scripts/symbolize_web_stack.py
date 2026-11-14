#!/usr/bin/env python3
"""Turns a minified web error report back into Dart (#132).

Web builds are minified by dart2js, so a report's error_type reads like
`minified:Ab` and its stack points into main.dart.js. Given the source map
of the same build, this prints the original Dart frames and type names.

Every web deploy keeps its map (firebase_deploy.yml): as the workflow
artifact `web-sourcemap-<version>` (90 days), and for production releases
also as the asset `main.dart.js.map` of the GitHub Release `v<version>`.

Usage:
  # The version is the report's app_version (a +build suffix is ignored).
  scripts/symbolize_web_stack.py --version 2026.11.20 < stack.txt
  scripts/symbolize_web_stack.py --version 2026.11.14-dev.3dbce7a stack.txt
  scripts/symbolize_web_stack.py --map build/web/main.dart.js.map stack.txt
  scripts/symbolize_web_stack.py --version 2026.11.20 --type minified:Ab

Downloading by version needs the GitHub CLI (`gh`) signed in to the repo.
Standard library only.
"""

from __future__ import annotations

import argparse
import bisect
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = "mazino2d/sim-split"
_B64 = {c: i for i, c in enumerate(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")}

# A frame's location in the bundle: Chrome `(https://…/main.dart.js:12:345)`,
# Firefox and Safari `name@https://…/main.dart.js:12:345`.
_FRAME = re.compile(r"(?:[\w.+-]+://[^\s()]*/)?main\.dart\.js:(\d+):(\d+)")
_MINIFIED = re.compile(r"minified:([A-Za-z_$][\w$]*)")


def _vlq(segment: str) -> list[int]:
    values, value, shift = [], 0, 0
    for char in segment:
        digit = _B64[char]
        value += (digit & 31) << shift
        if digit & 32:
            shift += 5
            continue
        values.append(-(value >> 1) if value & 1 else value >> 1)
        value, shift = 0, 0
    return values


class SourceMap:
    """A source map v3, with dart2js's table of minified names."""

    def __init__(self, data: dict):
        self.sources = data["sources"]
        self.names = data["names"]
        root = data.get("sourceRoot") or ""
        # App sources are relative to the build (../../../lib/…): show them
        # from the repo root.
        self.sources = [re.sub(r"^(\.\./)+", "", root + s)
                        for s in self.sources]
        # Per generated line: sorted columns and their (source, line, col,
        # name) mappings.
        self.lines: list[tuple[list[int], list[tuple]]] = []
        src = line = col = name = 0
        for text in data["mappings"].split(";"):
            gen_col = 0
            cols, maps = [], []
            for segment in filter(None, text.split(",")):
                fields = _vlq(segment)
                gen_col += fields[0]
                if len(fields) < 4:
                    continue
                src += fields[1]
                line += fields[2]
                col += fields[3]
                mapped_name = None
                if len(fields) > 4:
                    name += fields[4]
                    mapped_name = self.names[name]
                cols.append(gen_col)
                maps.append((self.sources[src], line, col, mapped_name))
            self.lines.append((cols, maps))
        self.minified: dict[str, dict[str, str]] = {}
        extension = data.get("x_org_dartlang_dart2js", {})
        for kind, table in extension.get("minified_names", {}).items():
            pairs = table.split(",") if table else []
            self.minified[kind] = {
                pairs[i]: self.names[int(pairs[i + 1])]
                for i in range(0, len(pairs) - 1, 2)
            }

    def lookup(self, line: int, column: int):
        """The mapping at a 1-based line and column, or None."""
        if not 0 < line <= len(self.lines):
            return None
        cols, maps = self.lines[line - 1]
        index = bisect.bisect_right(cols, column - 1) - 1
        return maps[index] if index >= 0 else None

    def type_name(self, minified: str) -> str | None:
        return self.minified.get("global", {}).get(minified)


def _download(version: str, into: Path) -> Path:
    version = version.split("+", 1)[0]
    is_dev = "-dev." in version or "-rc." in version
    if not is_dev:
        result = subprocess.run(
            ["gh", "release", "download", f"v{version}", "--repo", REPO,
             "--pattern", "main.dart.js.map", "--dir", str(into)],
            capture_output=True, text=True)
        if result.returncode == 0:
            return into / "main.dart.js.map"
    name = f"web-sourcemap-{version}"
    result = subprocess.run(
        ["gh", "run", "download", "--repo", REPO, "--name", name,
         "--dir", str(into)], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"No source map for {version}: neither the release asset nor "
                 f"the artifact {name} (kept 90 days).\n{result.stderr.strip()}")
    return into / "main.dart.js.map"


def symbolize(stack: str, source_map: SourceMap) -> str:
    def frame(match: re.Match) -> str:
        found = source_map.lookup(int(match[1]), int(match[2]))
        if found is None:
            return match[0]
        source, line, col, name = found
        where = f"{source}:{line + 1}:{col + 1}"
        return f"{where} ({name})" if name else where

    def type_name(match: re.Match) -> str:
        return source_map.type_name(match[1]) or match[0]

    return _MINIFIED.sub(type_name, _FRAME.sub(frame, stack))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--version", help="the report's app_version")
    source.add_argument("--map", type=Path, help="a local main.dart.js.map")
    parser.add_argument("--type", help="only translate this error_type, "
                        "e.g. minified:Ab")
    parser.add_argument("stack", nargs="?", type=Path,
                        help="file with the stack (default: stdin)")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        path = args.map or _download(args.version, Path(tmp))
        source_map = SourceMap(json.loads(path.read_text()))

    if args.type:
        print(symbolize(args.type, source_map))
        return
    text = args.stack.read_text() if args.stack else sys.stdin.read()
    print(symbolize(text, source_map), end="" if text.endswith("\n") else "\n")


if __name__ == "__main__":
    main()
