#!/usr/bin/env bash
# Builds Fable's patched DXMT: upstream 3Shain/dxmt at a pinned commit plus
# scripts/dxmt/patches/, in DXMT's *native* mode (-Dwine_builtin_dll=false).
#
# Why native: upstream's release tarball stamps every DLL as a Wine builtin.
# Wine treats a builtin-stamped file in a prefix's system32 as a placeholder
# and loads the copy from its own lib/wine instead (Wine's d3d11, not DXMT's),
# and refuses it outright under a "native" override. The only way to run the
# stamped build is to overwrite Wine's own d3d11/dxgi in lib/wine, which turns
# DXMT on for every bottle on that engine. In native mode d3d11, dxgi,
# d3d10core and nvapi64 are ordinary DLLs a per-bottle "n" override picks up;
# only winemetal.dll and nvngx.dll stay builtins (they need Wine's unix-call
# bridge), and Wine has no DLLs of those names, so they are found through
# WINEDLLPATH at launch with nothing written into the engine.
#
#   scripts/build-dxmt.sh [step...]   steps: fetch llvm win64 win32 package
#                                     (default: all, in order)
#   scripts/build-dxmt.sh clean       drops the source and build trees
#                                     (keeps downloads and the built LLVM)
#
# The recipe is upstream's own macOS release job (.github/workflows/ci.yml,
# "build-gcc-release-*-windows-cross"): Homebrew mingw-w64 for the PE DLLs,
# the 3Shain Wine 8.16 build for winebuild/winecrt0, and an x86_64 LLVM 15
# for airconv inside winemetal.so (Wine runs under Rosetta, so the unixlib
# is x86_64).
#
# Needs: Xcode with the Metal toolchain, Rosetta (the pinned winebuild is
# x86_64), Homebrew mingw-w64 meson ninja cmake.
#
# Output in build/dxmt/out/:
#   dxmt-<version>-native.tar.gz    the package (top folder v<version>/):
#       system32/ syswow64/        native DLLs, copied into the prefix
#       x86_64-windows/ i386-windows/ x86_64-unix/
#                                  builtins (winemetal, nvngx) + winemetal.so,
#                                  the WINEDLLPATH directory
#   dxmt-<version>-source.tar.gz    LGPL source: pinned upstream + patches
#   SHA256SUMS
set -euo pipefail

here=$(cd "$(dirname "$0")/dxmt" && pwd)
repo=$(cd "$here/../.." && pwd)
# shellcheck source=dxmt/pin.env
. "$here/pin.env"

work=${DXMT_WORK:-$repo/build/dxmt}
cache=$work/cache
src=$work/src
llvm=$work/llvm15-x86_64
toolchains=$work/toolchains
out=$work/out
jobs=${JOBS:-$(sysctl -n hw.ncpu)}
# Upstream's v0.80 winemetal.so has minos 15.0 (Xcode 16.1's default).
export MACOSX_DEPLOYMENT_TARGET=15.0

log() { printf '\n=== %s\n' "$*"; }
die() { echo "build-dxmt.sh: $*" >&2; exit 1; }

fetch_file() { # url sha256 dest
    if [ ! -f "$3" ]; then
        mkdir -p "$(dirname "$3")"
        curl -fsSL --retry 3 -o "$3.part" "$1" && mv "$3.part" "$3"
    fi
    echo "$2  $3" | shasum -a 256 -c - >/dev/null || die "checksum mismatch: $3 (delete it to re-download)"
}

step_fetch() {
    log "fetch DXMT ${DXMT_COMMIT:0:12} + $(ls "$here"/patches/*.patch | wc -l | tr -d ' ') patches"
    fetch_file "$DXMT_URL" "$DXMT_SHA256" "$cache/dxmt-$DXMT_COMMIT.tar.gz"
    fetch_file "$DXHEADERS_URL" "$DXHEADERS_SHA256" "$cache/mingw-directx-headers-$DXHEADERS_COMMIT.tar.gz"
    fetch_file "$NVAPI_URL" "$NVAPI_SHA256" "$cache/nvapi-$NVAPI_COMMIT.tar.gz"
    rm -rf "$src"; mkdir -p "$src/include/native/directx" "$src/external/nvapi"
    tar -xzf "$cache/dxmt-$DXMT_COMMIT.tar.gz" -C "$src" --strip-components=1
    tar -xzf "$cache/mingw-directx-headers-$DXHEADERS_COMMIT.tar.gz" -C "$src/include/native/directx" --strip-components=1
    tar -xzf "$cache/nvapi-$NVAPI_COMMIT.tar.gz" -C "$src/external/nvapi" --strip-components=1
    # A throwaway repository so `git am` keeps each patch's author and
    # meson's vcs_tag has something to describe.
    local g=(git -C "$src" -c user.name=fable-build -c user.email=build@localhost -c commit.gpgsign=false)
    "${g[@]}" init -q
    "${g[@]}" add -A
    "${g[@]}" commit -q -m "upstream 3Shain/dxmt $DXMT_COMMIT"
    "${g[@]}" am -q "$here"/patches/*.patch || die "a patch does not apply (see $src)"
}

step_llvm() {
    if [ "$(cat "$llvm/.pin" 2>/dev/null)" = "$LLVM_SHA256" ]; then log "LLVM $LLVM_VERSION x86_64: already built"; return; fi
    local tarball=$cache/llvm-project-$LLVM_VERSION.src.tar.xz b=$work/llvm-build
    log "LLVM $LLVM_VERSION x86_64 (log: $b/build.log; ~20 min)"
    fetch_file "$LLVM_URL" "$LLVM_SHA256" "$tarball"
    rm -rf "$b" "$llvm"; mkdir -p "$b/src"
    tar -xJf "$tarball" -C "$b/src" --strip-components=1 \
        "llvm-project-$LLVM_VERSION.src/llvm" "llvm-project-$LLVM_VERSION.src/cmake" "llvm-project-$LLVM_VERSION.src/third-party"
    # Upstream's setup-llvm-darwin flags, plus no tests/examples.
    cmake -B "$b/build" -S "$b/src/llvm" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$llvm" \
        -DCMAKE_OSX_ARCHITECTURES=x86_64 -DLLVM_HOST_TRIPLE=x86_64-apple-darwin \
        -DLLVM_ENABLE_ASSERTIONS=On -DLLVM_ENABLE_ZSTD=Off \
        -DCMAKE_CXX_FLAGS="-D_LIBCPP_KEEP_TRANSITIVE_INCLUDES_LLVM23" \
        -DLLVM_TARGETS_TO_BUILD="" -DLLVM_BUILD_TOOLS=Off -DLLVM_INCLUDE_BENCHMARKS=Off \
        -DLLVM_INCLUDE_TESTS=Off -DLLVM_INCLUDE_EXAMPLES=Off \
        -DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=Off > "$b/build.log" 2>&1 \
        || { tail -30 "$b/build.log"; die "LLVM configure failed"; }
    { cmake --build "$b/build" -j "$jobs" && cmake --install "$b/build"; } >> "$b/build.log" 2>&1 \
        || { tail -30 "$b/build.log"; die "LLVM build failed"; }
    echo "$LLVM_SHA256" > "$llvm/.pin"
    rm -rf "$b"
}

wine_toolchain() {
    arch -x86_64 /usr/bin/true 2>/dev/null || die "Rosetta is needed for the pinned winebuild: softwareupdate --install-rosetta"
    # `xcrun -f metal` finds a stub even when the toolchain is missing; running it tells.
    xcrun -sdk macosx metal --version >/dev/null 2>&1 || die "no Metal toolchain: xcodebuild -downloadComponent MetalToolchain"
    command -v x86_64-w64-mingw32-gcc >/dev/null || die "no mingw-w64: brew install mingw-w64"
    fetch_file "$WINE_URL" "$WINE_SHA256" "$cache/wine-8.16-3shain.tar.gz"
    if [ "$(cat "$toolchains/wine/.pin" 2>/dev/null)" != "$WINE_SHA256" ]; then
        rm -rf "$toolchains/wine"; mkdir -p "$toolchains/wine"
        tar -xzf "$cache/wine-8.16-3shain.tar.gz" -C "$toolchains/wine"
        echo "$WINE_SHA256" > "$toolchains/wine/.pin"
    fi
}

meson_build() { # name cross-file extra-options...
    local name=$1 cross=$2; shift 2
    local b=$work/build-$name
    [ "$name" = win64 ] && rm -rf "$work/install"   # stale files from an older layout
    [ -f "$src/meson.build" ] || die "no source: run the fetch step"
    wine_toolchain
    log "DXMT $name"
    meson setup --wipe "$b" "$src" --cross-file "$src/$cross" \
        --buildtype release --strip --prefix "$work/install" \
        -Dwine_install_path="$toolchains/wine" -Dwine_builtin_dll=false "$@" > "$b.log" 2>&1 \
        || { mkdir -p "$b"; tail -40 "$b.log"; die "meson setup ($name) failed"; }
    meson compile -C "$b" -j "$jobs" >> "$b.log" 2>&1 || { tail -40 "$b.log"; die "build ($name) failed"; }
    meson install -C "$b" >> "$b.log" 2>&1 || { tail -40 "$b.log"; die "install ($name) failed"; }
}

step_win64() {
    [ -f "$llvm/.pin" ] || die "no LLVM: run the llvm step"
    meson_build win64 build-win64.txt -Denable_nvapi=true -Denable_nvngx=true -Dnative_llvm_path="$llvm"
}

step_win32() {
    meson_build win32 build-win32.txt
}

step_package() {
    local name=dxmt-$DXMT_VERSION top=v$DXMT_VERSION stage=$work/stage
    log "package $name"
    rm -rf "$stage"; mkdir -p "$stage/$top" "$out"
    for d in system32 syswow64 x86_64-windows i386-windows x86_64-unix; do
        [ -d "$work/install/$d" ] || die "missing $d: run the win64 and win32 steps"
        cp -R "$work/install/$d" "$stage/$top/"
    done
    find "$stage" \( -name '*.a' -o -name '.DS_Store' \) -delete
    # Upstream v0.80's file set, split into native and builtin halves.
    local expected="i386-windows/winemetal.dll system32/d3d10core.dll system32/d3d11.dll system32/dxgi.dll system32/nvapi64.dll syswow64/d3d10core.dll syswow64/d3d11.dll syswow64/dxgi.dll x86_64-unix/winemetal.so x86_64-windows/nvngx.dll x86_64-windows/winemetal.dll"
    local actual
    actual=$(cd "$stage/$top" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
    [ "$actual" = "$expected" ] || die "unexpected package contents: $actual"
    # The builtins must carry Wine's stamp and the native DLLs must not.
    local f
    for f in x86_64-windows/winemetal.dll x86_64-windows/nvngx.dll i386-windows/winemetal.dll; do
        LC_ALL=C grep -aq 'Wine builtin DLL' "$stage/$top/$f" || die "$f is not stamped as a Wine builtin"
    done
    for f in system32/d3d11.dll system32/dxgi.dll syswow64/d3d11.dll syswow64/dxgi.dll; do
        LC_ALL=C grep -aq 'Wine builtin DLL' "$stage/$top/$f" && die "$f is stamped as a Wine builtin"
    done
    # Reproducible-ish archive: fixed owner, sorted entries.
    COPYFILE_DISABLE=1 tar --uid 0 --gid 0 --uname root --gname wheel -czf "$out/$name-native.tar.gz" -C "$stage" "$top"

    # LGPL source: the exact upstream archive and the patches, plus this
    # script and its pins so the binary can be rebuilt.
    local s=$work/source-stage/$name-source
    rm -rf "$work/source-stage"; mkdir -p "$s"
    cp "$cache/dxmt-$DXMT_COMMIT.tar.gz" "$cache/mingw-directx-headers-$DXHEADERS_COMMIT.tar.gz" "$cache/nvapi-$NVAPI_COMMIT.tar.gz" "$s/"
    cp -R "$here/patches" "$s/patches"
    cp "$here/pin.env" "$0" "$s/"
    COPYFILE_DISABLE=1 tar --uid 0 --gid 0 --uname root --gname wheel -czf "$out/$name-source.tar.gz" -C "$work/source-stage" "$name-source"

    (cd "$out" && shasum -a 256 "$name-native.tar.gz" "$name-source.tar.gz" > SHA256SUMS && cat SHA256SUMS)
}

if [ "${1:-}" = clean ]; then
    rm -rf "$src" "$work"/build-* "$work"/install* "$work/stage" "$work/source-stage"
    exit 0
fi
steps=("$@")
[ ${#steps[@]} -gt 0 ] || steps=(fetch llvm win64 win32 package)
for s in "${steps[@]}"; do
    case $s in
        fetch|llvm|win64|win32|package) "step_$s" ;;
        *) die "unknown step: $s" ;;
    esac
done
