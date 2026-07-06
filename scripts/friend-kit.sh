#!/bin/bash
# Assembles the Friend Kit: a single folder (and zip) a friend can use to go
# from nothing to playing.
#
#   scripts/friend-kit.sh [output-dir]
#
# Contents:
#   Fable-<version>.zip   — fresh app build
#   README.txt            — docs/FRIEND-README.md, the ritual + first-run guide
#   *.fbottle             — any bottle you exported into kit-payload/
#   Recipes/*.fablerecipe — any recipes you exported into kit-payload/Recipes/
#
# The .fbottle and recipes are YOURS to stage: export the donor Steam bottle
# from its bottle page (Export) and per-game recipes from Game Settings, drop
# them into kit-payload/. The script warns if the donor bottle is missing but
# still builds the kit — Fable works without one, just slower to set up.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
OUT="${1:-Friend-Kit-$VERSION}"
PAYLOAD="kit-payload"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "· building Fable.app ($VERSION)…"
./scripts/make-app.sh >/dev/null
ditto -c -k --sequesterRsrc --keepParent Fable.app "$OUT/Fable-$VERSION.zip"

cp docs/FRIEND-README.md "$OUT/README.txt"

shopt -s nullglob
bottles=("$PAYLOAD"/*.fbottle)
if [ ${#bottles[@]} -gt 0 ]; then
    cp "${bottles[@]}" "$OUT/"
    echo "· bundled ${#bottles[@]} bottle(s): ${bottles[*]##*/}"
else
    echo "! no .fbottle in $PAYLOAD/ — kit ships without a donor bottle."
    echo "  (Export one: bottle page → Export, save into $PAYLOAD/)"
fi

recipes=("$PAYLOAD"/Recipes/*.fablerecipe)
if [ ${#recipes[@]} -gt 0 ]; then
    mkdir -p "$OUT/Recipes"
    cp "${recipes[@]}" "$OUT/Recipes/"
    echo "· bundled ${#recipes[@]} recipe(s)"
fi

ditto -c -k --sequesterRsrc --keepParent "$OUT" "$OUT.zip"
echo "done: $OUT/ and $OUT.zip"
