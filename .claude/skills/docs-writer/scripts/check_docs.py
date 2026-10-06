#!/usr/bin/env python3
"""Check that relative links in the repo's docs resolve.

Scans tracked Markdown files and docs/*.html. A relative link must point to a
file or folder that exists; a #fragment on a Markdown target must match one of
its headings (GitHub slug rules). External links are not fetched.

Usage: python3 .claude/skills/docs-writer/scripts/check_docs.py [files...]
Exit code 1 if any link is broken.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
MD_LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)|^\[[^\]]+\]:\s+(\S+)", re.M)
IMG_LINK = re.compile(r"!\[[^\]]*\]\(([^)\s]+)\)")
HTML_LINK = re.compile(r"""(?:href|src)=["']([^"']+)["']""")
FENCE = re.compile(r"^(```|~~~).*?^\1", re.M | re.S)


def slug(heading: str) -> str:
    text = re.sub(r"`|\*\*|__|\[([^\]]*)\]\([^)]*\)", r"\1", heading.strip().lower())
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def anchors(path: Path) -> set[str]:
    body = FENCE.sub("", path.read_text(encoding="utf-8"))
    seen: dict[str, int] = {}
    out = set()
    for h in re.findall(r"^#{1,6}\s+(.+?)\s*#*$", body, re.M):
        s = slug(h)
        n = seen.get(s, 0)
        out.add(s if n == 0 else f"{s}-{n}")
        seen[s] = n + 1
    return out


def targets(path: Path):
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".md":
        text = FENCE.sub("", text)
        text = re.sub(r"`[^`\n]*`", "", text)
        for m in MD_LINK.finditer(text):
            yield m.group(1) or m.group(2)
        yield from IMG_LINK.findall(text)
    else:
        yield from HTML_LINK.findall(text)


def check(path: Path) -> list[str]:
    errors = []
    for raw in targets(path):
        if re.match(r"^[a-z][a-z0-9+.-]*:", raw, re.I) or raw.startswith("//"):
            continue  # http:, mailto:, data: …
        target, _, frag = raw.partition("#")
        target = target.split("?")[0]
        dest = (path.parent / target).resolve() if target else path
        if target.startswith("/"):
            dest = (ROOT / target.lstrip("/")).resolve()
        if not dest.exists():
            errors.append(f"{path.relative_to(ROOT)}: missing {raw}")
        elif frag and dest.suffix == ".md" and frag not in anchors(dest):
            errors.append(f"{path.relative_to(ROOT)}: no heading #{frag} in {raw}")
    return errors


def main() -> int:
    if len(sys.argv) > 1:
        files = [Path(f).resolve() for f in sys.argv[1:]]
    else:
        listed = subprocess.check_output(["git", "ls-files", "*.md", "docs/*.html"], cwd=ROOT, text=True)
        files = [ROOT / f for f in listed.split() if "node_modules" not in f]
    errors = [e for f in files if f.exists() for e in check(f)]
    print("\n".join(errors) or f"OK: {len(files)} files, all relative links resolve")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
