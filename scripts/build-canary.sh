#!/bin/zsh
# Builds Fable's engine canary (canary/fable-canary.c) into the app's
# resources. Needs mingw-w64 (`brew install mingw-w64`) — a developer's tool,
# so the built programs are committed: nobody building or running Fable needs
# it. Run this after changing the source, then update canary/SHA256SUMS (the
# script prints the new lines); a test fails if the two disagree, so the
# programs can't change without the source change being visible beside them.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="Sources/Fable/Resources/canary"
mkdir -p "$OUT"
FLAGS=(-O1 -s -static -Wall -Wextra -Wl,--no-insert-timestamp)

x86_64-w64-mingw32-gcc "${FLAGS[@]}" -o "$OUT/fable-canary64.exe" canary/fable-canary.c
i686-w64-mingw32-gcc "${FLAGS[@]}" -o "$OUT/fable-canary32.exe" canary/fable-canary.c

(cd "$OUT" && shasum -a 256 fable-canary64.exe fable-canary32.exe) | tee canary/SHA256SUMS
