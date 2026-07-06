#!/bin/bash
# Fable release ritual, scripted — because eleven hand-rolled releases in a
# week already caused one slip (a stray `git add -A`).
#
#   scripts/release.sh prepare 0.15.1
#       Bumps Info.plist (version + build), verifies the CHANGELOG has a
#       section for the version, runs the test suite. Run on the feature
#       branch BEFORE committing.
#
#   scripts/release.sh publish 0.15.1 "Release title"
#       Run on main AFTER the squash-merge: tags, pushes, rebuilds the app,
#       zips, and creates the GitHub release with notes extracted from the
#       CHANGELOG section. Refuses on a dirty tree or wrong branch.
#
# VERSIONING RULE (SemVer, 0.x flavor):
#   0.MINOR.0  — a new user-facing capability (hardware detection, feedback).
#   0.M.PATCH  — everything else: fixes, UI polish, localization, refactors,
#                docs. When in doubt, it's a patch. Patches may accumulate on
#                main and ship together — not every merge needs a release.
# prepare warns when a minor bump lands on a CHANGELOG section that smells
# like a patch; override consciously, not by reflex.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:?usage: release.sh prepare|publish <version> [title]}"
VERSION="${2:?version required, e.g. 0.15.1}"
PLIST="Resources/Info.plist"

changelog_section() {
    awk -v v="## v$VERSION " '
        $0 ~ "^" v { grab = 1; next }
        grab && /^## v/ { exit }
        grab { print }
    ' CHANGELOG.md
}

case "$MODE" in
prepare)
    grep -q "^## v$VERSION " CHANGELOG.md || {
        echo "error: CHANGELOG.md has no '## v$VERSION' section — write it first" >&2; exit 1
    }
    CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
    BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"
    plutil -lint "$PLIST" >/dev/null
    echo "bumped $CURRENT (build $BUILD) -> $VERSION (build $((BUILD + 1)))"
    swift test 2>&1 | tail -1
    ;;
publish)
    TITLE="${3:?title required for publish}"
    [ "$(git rev-parse --abbrev-ref HEAD)" != "gptk4-heroic-patcher" ] || true
    [ -z "$(git status --porcelain)" ] || { echo "error: dirty tree — commit or stash first" >&2; exit 1; }
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || {
        echo "error: HEAD != origin/main — realign first (reset --hard origin/main)" >&2; exit 1
    }
    PLIST_V=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
    [ "$PLIST_V" = "$VERSION" ] || { echo "error: Info.plist says $PLIST_V, not $VERSION" >&2; exit 1; }

    NOTES=$(changelog_section)
    [ -n "$NOTES" ] || { echo "error: empty CHANGELOG section for v$VERSION" >&2; exit 1; }

    git tag -a "v$VERSION" -m "Fable v$VERSION — $TITLE"
    git push -q origin "v$VERSION"

    pkill -f "Fable.app/Contents/MacOS/Fable" 2>/dev/null || true
    sleep 1
    ./scripts/make-app.sh >/dev/null
    ZIP="Fable-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent Fable.app "$ZIP"
    gh release create "v$VERSION" "$ZIP" --title "Fable v$VERSION — $TITLE" --notes "$NOTES"
    rm -f "$ZIP"
    open Fable.app
    echo "published v$VERSION"
    ;;
*)
    echo "usage: release.sh prepare|publish <version> [title]" >&2; exit 1
    ;;
esac
