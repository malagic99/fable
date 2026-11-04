#!/bin/bash
# Builds Fable's native Steam bridge on this Mac.
#
#   scripts/steam-bridge/build.sh [OUT_DIR]
#
# The bridge is Valve's Proton `lsteamclient` (Steamworks SDK licence — so
# Fable ships this script, never the code or the built files), compiled
# against Wine 10.0 for Sikarugir, plus Fable's small macOS patch and a
# `steam.exe` stand-in. A Windows game's steam_api then talks to the native
# Mac Steam client. Plan and spike results: docs/NATIVE-STEAM-BRIDGE.md.
#
# Output (OUT_DIR, default: Fable's components folder):
#   x86_64-windows/{lsteamclient,steamclient64}.dll
#   i386-windows/{lsteamclient,steamclient}.dll
#   x86_64-unix/{lsteamclient,steamclient64,steamclient}.so
#   steam.exe          the stand-in
#   manifest.json      pins + SHA-256 of every file above
#
# Fable puts OUT_DIR on WINEDLLPATH for bridge launches only; Sikarugir
# itself is never modified.
#
# Needs: Xcode command-line tools, Rosetta, Homebrew mingw-w64, bison (3.x),
# autoconf. Network: wine-10.0 tarball (dl.winehq.org) and a sparse Proton
# checkout (github.com/ValveSoftware/Proton), both pinned below.
set -euo pipefail
cd "$(dirname "$0")"
HERE=$(pwd)

BRIDGE_VERSION=1
WINE_VERSION=10.0
WINE_URL=https://dl.winehq.org/wine/source/10.0/wine-10.0.tar.xz
WINE_SHA256=c5e0b3f5f7efafb30e9cd4d9c624b85c583171d33549d933cd3402f341ac3601
PROTON_REPO=https://github.com/ValveSoftware/Proton
PROTON_COMMIT=e91ca2be0df2cef4c230cbbc0b86604d73a0bbf6   # proton_10.0

FABLE_SUPPORT="$HOME/Library/Application Support/Fable"
OUT="${1:-$FABLE_SUPPORT/Components/steam-bridge/$BRIDGE_VERSION}"
WORK="${STEAM_BRIDGE_WORK:-$HOME/Library/Caches/Fable/steam-bridge-build}"
SIKARUGIR_NTDLL=$(find "$FABLE_SUPPORT/Components/sikarugir" -path "*x86_64-unix/ntdll.so" 2>/dev/null | head -1)

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# MARK: Tools
BISON_DIR=/opt/homebrew/opt/bison/bin
for tool in x86_64-w64-mingw32-gcc i686-w64-mingw32-gcc clang clang++ flex autoconf; do
    command -v "$tool" >/dev/null || die "missing $tool (brew install mingw-w64 autoconf; xcode-select --install)"
done
[ -x "$BISON_DIR/bison" ] || die "missing Homebrew bison 3.x (brew install bison)"
arch -x86_64 /usr/bin/true 2>/dev/null || die "Rosetta is required (softwareupdate --install-rosetta)"
[ -n "$SIKARUGIR_NTDLL" ] || die "Sikarugir isn't installed in Fable — install it first (the bridge links its ntdll.so)"
mkdir -p "$WORK"

# MARK: Sources
say "Wine $WINE_VERSION source"
TARBALL="$WORK/wine-$WINE_VERSION.tar.xz"
[ -f "$TARBALL" ] || curl -fL --retry 3 -o "$TARBALL" "$WINE_URL"
echo "$WINE_SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null || die "wine tarball checksum mismatch"

say "Proton lsteamclient @ ${PROTON_COMMIT:0:7}"
PROTON="$WORK/proton"
if [ "$(git -C "$PROTON" rev-parse HEAD 2>/dev/null)" != "$PROTON_COMMIT" ]; then
    rm -rf "$PROTON"
    git init -q "$PROTON"
    git -C "$PROTON" remote add origin "$PROTON_REPO"
    git -C "$PROTON" sparse-checkout set --no-cone lsteamclient
    git -C "$PROTON" fetch -q --depth 1 --filter=blob:none origin "$PROTON_COMMIT"
    git -C "$PROTON" checkout -q FETCH_HEAD
fi

# MARK: Wine tree with lsteamclient as a module
say "Preparing the Wine tree"
SRC="$WORK/wine-$WINE_VERSION"
rm -rf "$SRC"
tar -xf "$TARBALL" -C "$WORK"
MOD="$SRC/dlls/lsteamclient"
cp -R "$PROTON/lsteamclient" "$MOD"
patch -s -d "$SRC/dlls" -p1 < "$HERE/lsteamclient-macos.patch"
cp "$HERE/fable_compat.cpp" "$MOD/"
# Upstream Wine's makedep can't compile C++ (Proton's Wine fork adds that):
# the Windows half stays in Makefile.in, the C++ Unix half is built below.
python3 - "$MOD" <<'PY'
import re, sys, pathlib
mod = pathlib.Path(sys.argv[1])
mk = mod / "Makefile.in"
keep, cpp = [], []
for line in mk.read_text().split("\n"):
    item = line.strip().rstrip("\\").strip()
    if item.endswith(".cpp"):
        cpp.append(item)
    elif not line.startswith("UNIXLIB"):
        keep.append(line)
for i, line in enumerate(keep):           # drop a continuation left dangling
    nxt = keep[i + 1] if i + 1 < len(keep) else ""
    if line.rstrip().endswith("\\") and not nxt.strip():
        keep[i] = line.rstrip()[:-1].rstrip()
mk.write_text("\n".join(keep).rstrip("\n") + "\n")
(mod / "unix_sources.txt").write_text("\n".join(cpp + ["fable_compat.cpp"]) + "\n")
PY
sed -i '' 's|^WINE_CONFIG_MAKEFILE(dlls/lz32)$|WINE_CONFIG_MAKEFILE(dlls/lsteamclient)\
WINE_CONFIG_MAKEFILE(dlls/lz32)|' "$SRC/configure.ac"
grep -q 'WINE_CONFIG_MAKEFILE(dlls/lsteamclient)' "$SRC/configure.ac" || die "couldn't register the module"
(cd "$SRC" && PATH="$BISON_DIR:$PATH" autoconf)

# MARK: Windows half
# Under Rosetta, Apple's compiler shim still targets arm64 unless told.
say "Configuring Wine (x86_64, under Rosetta)"
BLD="$WORK/wine64"
rm -rf "$BLD" && mkdir -p "$BLD"
ROSETTA_PATH="$BISON_DIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
(cd "$BLD" && arch -x86_64 /usr/bin/env PATH="$ROSETTA_PATH" "$SRC/configure" \
    CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
    --enable-archs=x86_64,i386 --disable-tests \
    --without-x --without-freetype --without-gstreamer --without-cups --without-gphoto \
    --without-sane --without-pcap --without-krb5 --without-gnutls --without-sdl \
    --without-opencl --without-vulkan --without-capi --without-v4l2 --without-netapi \
    --without-usb --without-pulse --without-dbus --without-inotify --without-osmesa \
    --without-opengl --without-oss --without-udev --without-unwind --without-gettext \
    --without-coreaudio --without-pthread > configure.log 2>&1) \
    || die "configure failed — see $BLD/configure.log"

say "Building the Windows half"
(cd "$BLD" && arch -x86_64 /usr/bin/env PATH="$ROSETTA_PATH" \
    make -j"$(sysctl -n hw.ncpu)" dlls/lsteamclient/all > make.log 2>&1) \
    || die "make failed — see $BLD/make.log"

# MARK: Unix half
say "Building the Unix half"
UNIX_OUT="$BLD/dlls/lsteamclient/unix"
mkdir -p "$UNIX_OUT"
#   __WINESRC__            Wine's short ERR/FIXME macros
#   WINE_NO_INLINE_STRING  else winbase.h poisons wcsncpy against <wchar.h>
#   NOMINMAX               windef.h's max() vs std::max
RSP="$UNIX_OUT/cxxflags.rsp"
printf '%s\n' -arch x86_64 -std=gnu++17 -O2 -fPIC -fvisibility=hidden \
    -D__WINESRC__ -DWINE_UNIX_LIB -D_REENTRANT -DNOMINMAX -DWINE_NO_INLINE_STRING \
    -DSTEAM_API_EXPORTS -Dprivate=public -Dprotected=public \
    "-I$MOD" "-I$BLD/include" "-I$SRC/include" -Wno-everything > "$RSP"
objs=()
pairs=()
while read -r src; do
    [ -n "$src" ] || continue
    objs+=("$UNIX_OUT/${src%.cpp}.o")
    pairs+=("$MOD/$src" "$UNIX_OUT/${src%.cpp}.o")
done < "$MOD/unix_sources.txt"
printf '%s\0' "${pairs[@]}" \
    | RSP="$RSP" xargs -0 -n 2 -P "$(sysctl -n hw.ncpu)" \
        sh -c 'clang++ @"$RSP" -c "$1" -o "$2"' _ 2> "$UNIX_OUT/compile.log" \
    || die "Unix half failed to compile — see $UNIX_OUT/compile.log"
clang++ -arch x86_64 -dynamiclib -install_name lsteamclient.so -Wl,-undefined,error \
    "${objs[@]}" "$SIKARUGIR_NTDLL" -o "$UNIX_OUT/lsteamclient.so"
# Link the way Sikarugir's own unix libs do.
install_name_tool -change ntdll.so @rpath/ntdll.so "$UNIX_OUT/lsteamclient.so" 2>/dev/null
install_name_tool -add_rpath @loader_path/ "$UNIX_OUT/lsteamclient.so" 2>/dev/null

# MARK: Stand-in
say "Building the steam.exe stand-in"
x86_64-w64-mingw32-gcc -municode -O2 -o "$WORK/steam.exe" "$HERE/steam-shim.c"

# MARK: Assemble
# A builtin's Unix half is found by the DLL's own name, and steam_api asks for
# steamclient64/steamclient — so the bridge is installed under those names too.
say "Assembling $OUT"
STAGE="$OUT.partial"
rm -rf "$STAGE"
mkdir -p "$STAGE/x86_64-windows" "$STAGE/i386-windows" "$STAGE/x86_64-unix"
cp "$BLD/dlls/lsteamclient/x86_64-windows/lsteamclient.dll" "$STAGE/x86_64-windows/lsteamclient.dll"
cp "$BLD/dlls/lsteamclient/x86_64-windows/lsteamclient.dll" "$STAGE/x86_64-windows/steamclient64.dll"
cp "$BLD/dlls/lsteamclient/i386-windows/lsteamclient.dll" "$STAGE/i386-windows/lsteamclient.dll"
cp "$BLD/dlls/lsteamclient/i386-windows/lsteamclient.dll" "$STAGE/i386-windows/steamclient.dll"
for name in lsteamclient steamclient64 steamclient; do
    cp "$UNIX_OUT/lsteamclient.so" "$STAGE/x86_64-unix/$name.so"
    install_name_tool -id "$name.so" "$STAGE/x86_64-unix/$name.so" 2>/dev/null
    codesign -f -s - "$STAGE/x86_64-unix/$name.so" 2>/dev/null
done
cp "$WORK/steam.exe" "$STAGE/steam.exe"

python3 - "$STAGE" "$BRIDGE_VERSION" "$WINE_VERSION" "$PROTON_COMMIT" <<'PY'
import hashlib, json, pathlib, sys
stage, version, wine, proton = sys.argv[1:]
root = pathlib.Path(stage)
files = {
    str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in sorted(root.rglob("*")) if p.is_file()
}
manifest = {"bridgeVersion": int(version), "wine": wine, "protonCommit": proton, "files": files}
(root / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
rm -rf "$OUT"
mv "$STAGE" "$OUT"
say "Done: $OUT"
