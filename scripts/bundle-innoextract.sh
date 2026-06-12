#!/bin/zsh
# Embeds innoextract (and its Homebrew dylibs) into Fable.app so users
# don't need Homebrew for GOG installer extraction.
# Usage: bundle-innoextract.sh <path-to-Fable.app>
set -euo pipefail

APP="$1"
SOURCE="${INNOEXTRACT:-/opt/homebrew/bin/innoextract}"

if [[ ! -x "$SOURCE" ]]; then
    echo "innoextract not found at $SOURCE — skipping bundling (app falls back to Homebrew lookup)"
    exit 0
fi

MACOS_DIR="$APP/Contents/MacOS"
FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS"

cp "$SOURCE" "$MACOS_DIR/innoextract"
chmod 755 "$MACOS_DIR/innoextract"

# Recursively collect non-system dylib dependencies.
typeset -A seen
queue=("$MACOS_DIR/innoextract")
while (( ${#queue[@]} > 0 )); do
    bin="${queue[1]}"; queue=("${queue[@]:1}")
    for dep in $(otool -L "$bin" | awk 'NR>1 {print $1}' | grep -E '^/opt/homebrew|^/usr/local' || true); do
        name="$(basename "$dep")"
        if [[ -z "${seen[$name]:-}" ]]; then
            seen[$name]=1
            cp "$dep" "$FRAMEWORKS/$name"
            chmod 644 "$FRAMEWORKS/$name"
            queue+=("$FRAMEWORKS/$name")
        fi
        install_name_tool -change "$dep" "@executable_path/../Frameworks/$name" "$bin" 2>/dev/null
    done
done

# Fix each bundled dylib's own id and re-sign everything we touched.
for dylib in "$FRAMEWORKS"/*.dylib(N); do
    install_name_tool -id "@executable_path/../Frameworks/$(basename "$dylib")" "$dylib" 2>/dev/null
    codesign --force --sign - "$dylib"
done
codesign --force --sign - "$MACOS_DIR/innoextract"

echo "Bundled innoextract with ${#seen[@]} dylibs"
