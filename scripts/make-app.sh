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
# SwiftPM resource bundle (versions.json etc.) — Bundle.module finds it
# via Bundle.main.resourceURL when placed in Contents/Resources.
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
plutil -insert CFBundleLocalizations -array "$APP/Contents/Info.plist" 2>/dev/null || true
for lang in $(ls "$RESOURCE_BUNDLE" | grep '\.lproj$' | sed 's/\.lproj$//'); do
    plutil -insert "CFBundleLocalizations.0" -string "$lang" -append "$APP/Contents/Info.plist" 2>/dev/null || true
done

# Embed innoextract for GOG installer extraction (no-op if not installed).
"$(dirname "$0")/bundle-innoextract.sh" "$APP"

# Ad-hoc signature so macOS will launch it locally without a developer cert.
codesign --force --sign - "$APP"

echo "Done: $(pwd)/$APP"
