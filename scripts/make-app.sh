#!/bin/zsh
# Builds Fable.app at the repo root. Double-click it or `open Fable.app`.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building release binary..."
swift build -c release

APP="Fable.app"
BIN=".build/release/Fable"
RESOURCE_BUNDLE=".build/release/Fable_Fable.bundle"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Fable"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Fable.icns "$APP/Contents/Resources/Fable.icns"
# SwiftPM resource bundle (versions.json, .lproj). Contents/Resources is the
# right place for an .app, but SwiftPM's generated Bundle.module does NOT look
# here — it checks beside the executable, then an absolute path inside the
# build directory of whichever machine compiled it. That second path exists
# only on the build machine, so a mislocated bundle still launches here and
# SIGTRAPs everywhere else (v0.23.3 shipped exactly that). The app reads
# resources through Bundle.fableResources, which looks here first.
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"

# Mirror .lproj directories from the SwiftPM bundle into the app's main
# Resources so SwiftUI's automatic LocalizedStringKey lookup (Bundle.main,
# not Bundle.module) actually finds them. Without this, Text("foo.bar")
# in SwiftUI renders the raw key while L10n.string() works fine.
for lproj in "$RESOURCE_BUNDLE"/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done

# Tell macOS which locales we ship so it picks the right one at launch.
# Without CFBundleLocalizations the app falls back to development region only.
LANGS=$(ls "$RESOURCE_BUNDLE" | grep '\.lproj$' | sed 's/\.lproj$//' | paste -sd ',' - | sed 's/\([^,]*\)/"\1"/g')
plutil -replace CFBundleLocalizations -json "[${LANGS}]" "$APP/Contents/Info.plist"

# Embed innoextract for GOG installer extraction (no-op if not installed).
"$(dirname "$0")/bundle-innoextract.sh" "$APP"

# Ad-hoc signature so macOS will launch it locally without a developer cert.
codesign --force --sign - "$APP"

echo "Done: $(pwd)/$APP"
