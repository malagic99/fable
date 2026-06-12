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

# Ad-hoc signature so macOS will launch it locally without a developer cert.
codesign --force --sign - "$APP"

echo "Done: $(pwd)/$APP"
