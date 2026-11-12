#!/usr/bin/env python3
"""Records what a Fable.app was built from.

    build-info.py app <Fable.app>
        Writes Contents/Resources/build-info.json: version, build number, the
        git commit, whether the tree had uncommitted changes, the compiler,
        and the SHA-256 of each tool bundled from the build machine. The app
        shows the commit in Settings → About and in feedback reports, so a
        report can be matched to the exact source it came from.

    build-info.py release <Fable.app> <Fable-x.y.z.zip> <out.json>
        The same record plus the SHA-256 of the zip, for publishing beside a
        release so a download can be checked against it.
"""
import datetime
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys


def run(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_info(app):
    app = pathlib.Path(app)
    with open(app / "Contents/Info.plist", "rb") as handle:
        plist = plistlib.load(handle)
    status = run("git", "status", "--porcelain", "--untracked-files=no")
    swift = (run("swift", "--version") or "").splitlines()
    bundled = {}
    for name in ("cabextract", "innoextract"):
        tool = app / "Contents/MacOS" / name
        if tool.exists():
            bundled[name] = sha256(tool)
    catalog = next(app.glob("Contents/Resources/*.bundle/**/versions.json"), None)
    return {
        "schemaVersion": 1,
        "version": plist.get("CFBundleShortVersionString"),
        "build": plist.get("CFBundleVersion"),
        "commit": run("git", "rev-parse", "HEAD"),
        # None when git couldn't say; a release must be False.
        "dirty": None if status is None else bool(status),
        "builtAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "swift": swift[0] if swift else None,
        "bundledTools": bundled,
        "componentCatalogSHA256": sha256(catalog) if catalog else None,
    }


def main(argv):
    if len(argv) == 3 and argv[1] == "app":
        info = build_info(argv[2])
        out = pathlib.Path(argv[2]) / "Contents/Resources/build-info.json"
        out.write_text(json.dumps(info, indent=2) + "\n")
        print(f"build info: {info['version']} from {(info['commit'] or 'unknown')[:7]}"
              + (" + uncommitted changes" if info["dirty"] else ""))
        return 0
    if len(argv) == 5 and argv[1] == "release":
        embedded = pathlib.Path(argv[2]) / "Contents/Resources/build-info.json"
        info = json.loads(embedded.read_text())
        zip_path = pathlib.Path(argv[3])
        info["artifact"] = {"name": zip_path.name, "sha256": sha256(zip_path)}
        pathlib.Path(argv[4]).write_text(json.dumps(info, indent=2) + "\n")
        print(info["artifact"]["sha256"])
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
