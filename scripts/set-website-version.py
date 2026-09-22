#!/usr/bin/env python3
"""Set the version shown on the marketing site.

The page asks GitHub for the latest release at load time, but the version is
also written into the markup so it reads correctly before that call returns —
and when it never does, which is the case offline and once a visitor's IP hits
GitHub's 60-requests-an-hour unauthenticated limit. That fallback is only
useful if it isn't stale, so release.sh sets it as part of preparing a release
rather than leaving it to be remembered.

The page is a self-unpacking bundle: the real document is a JSON string on one
line of index.html, and every closing tag inside it is escaped as `<\\u002F`
so the payload can't terminate the <script> element that carries it. Both
properties have to survive editing, so the string is decoded, changed, and
re-encoded with that escaping restored.

Usage: set-website-version.py 0.23.5 [path/to/index.html]
"""

import json
import re
import sys
from pathlib import Path

VERSION_ATTRIBUTE = "data-fable-version"
VERSION_PATTERN = re.compile(r"v\d+\.\d+\.\d+")

# Built by concatenation rather than written as a literal: a source-level
# "/" is liable to be collapsed back into "/" by whatever hands this file
# around, which turns the escaping step below into a silent no-op and produces
# a page that cannot load. chr(92) is a backslash.
ESCAPED_CLOSING_TAG = "<" + chr(92) + "u002F"


def set_version(page: Path, version: str) -> int:
    lines = page.read_text(encoding="utf-8").split("\n")

    template_index = next(
        (i for i, line in enumerate(lines) if VERSION_ATTRIBUTE in line), None
    )
    if template_index is None:
        raise SystemExit(
            f"error: no element carrying {VERSION_ATTRIBUTE} in {page} — "
            "the page changed shape; update this script with it"
        )

    html = json.loads(lines[template_index])

    # Rewrite only the version inside elements that opted in by carrying the
    # attribute, so prose mentioning a version is left alone.
    replaced = 0

    def rewrite(match: re.Match) -> str:
        nonlocal replaced
        element = match.group(0)
        element, count = VERSION_PATTERN.subn(f"v{version}", element, count=1)
        replaced += count
        return element

    html = re.sub(rf"<[^<>]*{VERSION_ATTRIBUTE}[^<>]*>[^<]*", rewrite, html)
    if replaced == 0:
        raise SystemExit(f"error: found {VERSION_ATTRIBUTE} but no version text to set")

    encoded = json.dumps(html, ensure_ascii=False).replace("</", ESCAPED_CLOSING_TAG)
    if json.loads(encoded) != html:
        raise SystemExit("error: re-encoding changed the page content")
    if "</" in encoded:
        raise SystemExit("error: an unescaped closing tag would break the bundle")

    lines[template_index] = encoded
    page.write_text("\n".join(lines), encoding="utf-8")
    return replaced


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    target = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("website/index.html")
    count = set_version(target, sys.argv[1].lstrip("v"))
    print(f"website: set {count} version site(s) to v{sys.argv[1].lstrip('v')}")
