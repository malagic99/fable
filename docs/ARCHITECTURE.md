# Fable architecture — why the stack is shaped this way

This is the systems companion to [wine-quirks.md](wine-quirks.md). Quirks says
*where each fix lives*; this file says *why the design is what it is*, records
the hard-won findings behind it, and lists the dead ends so nobody re-walks
them. Everything here was empirically verified on an M4 Pro (2026-06); dates
mark when.

## The thesis: the matched pair

A modern D3D12 game needs **two things at once**:

1. **Modern Wine SEH** — MSVC C++ exceptions the game throws must unwind.
   Wine 7.7 (Apple's GPTK base) can't → deterministic `int3` /
   `EXCEPTION_BREAKPOINT` at the same game offset every run.
2. **Real D3D12→Metal** — Apple's D3DMetal, the only production-quality
   D3D12 translation on macOS (vkd3d-proton has no macOS port; DXVK-macOS
   is D3D11-only).

The catch: D3DMetal's *dispatch layer* ({d3d11,d3d12,dxgi,nvapi64}.dll +
.so) is **ABI-locked to the exact Wine it was built against**. Apple ships it
built against wine-7.7. Mixing (modern wine + Apple's 7.7 dispatch, or
CrossOver's dispatch on a from-source wine) → `c0000142` DLL-init failure or
`c0000005` crashes (PE↔unix thunks misaligned).

**The answer is a matched pair: a modern Wine + a D3DMetal dispatch
recompiled against THAT wine.** Two products ship one:

- **Sikarugir** (free, GPL): wine-10.0 + `renderer/d3dmetal/` built against
  it. This is Fable's flagship backend (`SikarugirManager`).
- **CrossOver** (paid): its own wine fork + D3DMetal licensed and rebuilt
  against it.

Only `D3DMetal.framework` itself is Apple's and **cannot be redistributed** —
Fable discovers/imports it from the user's Sikarugir or GPTK install (the
onboarding D3DMetal step), never bundles it.

## The stack

```
game.exe (x86_64 Windows)
  → Wine (x86_64 mac binary, under Rosetta 2 — games are x86, that's fine)
    → renderer builtins (d3d12.dll/.so — WHICH set is the "backend" choice)
      → D3DMetal.framework / DXMT / DXVK+MoltenVK
        → Metal
```

`ROSETTA_ADVERTISE_AVX=1` on every launch: Rosetta hides AVX by default and
games CPU-gate on it (`rosetta-avx-flag`). Sync primitive is **msync**
(`WINEMSYNC=1`) on Sikarugir — see the WoW64 section for why esync is poison.

## The six backends

| Backend | What it is | When |
|---|---|---|
| `sikarugir` | wine-10.0 + matched D3DMetal (flagship) | D3D12, Steam client, modern AAA |
| `dxmt` | DirectX 10/11 → Metal directly | D3D11 games, often fastest for them |
| `dxvk` | DX → Vulkan → MoltenVK → Metal | D3D9–11 fallback, quirky titles |
| `crossover` | Runs the bottle on the user's installed CrossOver | If they own it; reference renderer |
| `gptk` | Apple GPTK, wine-7.7 | Legacy; broken for modern SEH — kept for the few titles that want it |
| `off` | Wine's built-in wined3d ("Built-in") | D3D9–11 older games; NOT "no Wine" |

## The renderer-directory mechanism (validated against CrossOver 26.2)

CrossOver, Sikarugir, and GPTK all share one architecture: each translation
layer is a **self-contained directory of ABI-matched DLLs** overlaid into the
Wine lib path. CrossOver's toggle is a single env var in `cxbottle.conf`:
`CX_GRAPHICS_BACKEND = wined3d | dxvk | d3dmetal | dxmt`, resolved by its Perl
`bin/wine` wrapper into which renderer dir wins on `WINEDLLPATH`. It also
exports `CX_APPLEGPTK_LIBD3DSHARED_PATH` unconditionally, and maps
`WINEESYNC=1 → WINEMSYNC=1` (CrossOver moved to msync too).

Fable does the same thing with different plumbing: `SikarugirManager.overlay()`
copies the renderer's matched DLLs, and `WINEDLLOVERRIDES=d3d11,d3d12,dxgi,
nvapi64=b` forces the builtins. Same outcome: *the renderer's* d3d12 loads
instead of wined3d. This teardown is why we trust the design — it's the
commercial reference implementation's own shape.

## The ABI law (learned three times, don't learn it a fourth)

> Anything that crosses the Wine PE↔unix boundary — renderer dispatch `.so`s,
> `winemac.drv` — only works with the Wine it was compiled against.

- Apple GPTK-4 dispatch on wine-7.7 base: `___wine_unix_call_funcs` (wine 8+)
  vs `__wine_init_unix_lib` (old) → `c0000142` before `main()`.
- CrossOver's winemac.drv dropped into upstream wine 11: killed the CEF GPU
  crash-loop but still black (and it's ABI-luck it loaded at all).
- CrossOver's D3DMetal dispatch on our from-source CrossOver wine build:
  `c0000005`.

Corollary: you never "just copy the driver" — you ship the matched pair or
you build both from the same source.

## The Steam CEF saga (condensed; full detail in git history)

Steam's login/UI is Chromium (CEF), and it was a black square on every
upstream-Wine configuration. The investigation, in order:

1. **Not flags.** Every CEF flag combo on `Steam.exe` failed — Steam ignores
   GPU flags passed to `Steam.exe`; they must reach the `steamwebhelper.exe`
   subprocess, which Steam self-integrity-restores if you shim the binary.
2. **Not the driver alone.** Built CrossOver 26.2's winemac.drv (and later
   the complete CrossOver wine) from LGPL source. GPU crash-loop gone, still
   black: ANGLE got only a legacy GL context and a **degenerate 1×1 window
   surface** — the compositing path needs the D3DMetal-backed window surface
   wiring, not a GL-version tweak (forcing core-profile GL4 changed nothing).
3. **The actual missing piece was env wiring on the matched pair.**
   `D3DMETAL_FRAMEWORK_PATH` pointing at the bundle's framework (plus
   `CX_APPLEGPTK_LIBD3DSHARED_PATH`, builtins override) — without it,
   `d3d11.so` can't `dlopen` D3DMetal → no Metal client surface → black.
   Plus staging Sikarugir's support dylibs into the engine: **libfreetype**
   (no font lib → DirectWrite renders no text at all) and **libgnutls/libgmp**
   (no TLS → HTTPS dead → the login QR never loads). All productized in
   `SikarugirManager.launchEnvironment` + `backfillSupportLibs`.
4. **Perf reality — do not re-litigate:** Steam's CEF GUI runs in **software
   on every Wine-on-macOS stack, CrossOver included** (its own
   `webhelper_gpu.txt` says `Disabling GPU acceleration: Disabled/CommandLine`).
   There is no GPU Steam GUI to unlock; Fable is at parity with the paid
   product here. GUI sluggishness = software Chromium + Rosetta tax. Real
   levers: Steam Settings → disable smooth scrolling/animations, Library Low
   Performance Mode. **Games** are unaffected — they render through D3DMetal.

## WoW64 gaps (Steam installs, GOG installers)

Sikarugir's wine is an **experimental-WoW64** build (no `i386-unix`): 32-bit
processes run through a 64-bit compatibility layer, and two things break:

- **`steamservice.exe` (32-bit) named-pipe IPC** fails → Steam downloads and
  extracts but the final *commit* ("installing files") hands off to a dead
  service. Two-part fix: **`WINEMSYNC=1`** is the headline (esync's eventfd
  waits degrade into a CPU spin under Rosetta — Steam's IOCP threads pinned
  411% CPU at 0 Mbps; msync blocks properly: 32% CPU, 60+ Mbps), and
  `SteamInstallCommitter` is the safety net that finishes any still-stuck,
  fully-extracted install (moves `downloading/` → `common/`, writes the
  Installed manifest). Runs on bottle open + a button.
- **GOG/InnoSetup installers SIGKILL** under WoW64 on all mac Wine builds →
  Fable extracts them with bundled `innoextract` instead of running them.
  Gotcha: a quarantine xattr on the extracted payload also SIGKILLs.

## Anti-tamper: the First Light rule

Some games (e.g. 007 First Light) hit an **identical `int3` in the game's own
code on every backend** — GPTK, DXVK, Sikarugir, and CrossOver alike — while
running perfectly on real Windows. That's a game-side anti-Wine/anti-tamper or
Rosetta CPU-feature gate, not a graphics problem; **no backend choice fixes
it**. Heuristic (worth surfacing in Smart Bottle/Doctor): *runs on Windows +
same int3 across ≥2 macOS backends ⇒ stop switching backends; the honest
answer is PC streaming (Moonlight/Sunshine/Steam Link).* Never fake a
"verified" for these.

## Shader cache

D3DMetal compiles pipelines into
`$DARWIN_USER_CACHE_DIR/<wine-bundle-id>/com.apple.metal` — **volatile; macOS
purges it on reboot**, which re-introduces first-run stutter on warmed games.
`ShaderCache` snapshots/restores it at startup (matching only wine-named
bundle ids, never `com.apple.*`), keyed by GPU + driver build. There is no
Fossilize equivalent — pre-building shaders isn't possible; preserving the
cache is the whole play.

## Dead ends — checked, closed, don't re-attempt blindly

| Attempt | Result | Why |
|---|---|---|
| Steam in-game overlay (Shift+Tab) | Composites black | Cross-process CEF GPU-shared texture fails on D3DMetal; CrossOver-level Wine work. Controller config from the main Steam window works. |
| CrossOver winemac.drv drop-in | Black square persists | ABI + the fix needs the D3DMetal window-surface runtime, not the driver alone |
| CEF flags on Steam.exe | Ignored | Flags must reach steamwebhelper; Steam restores modified binaries |
| steamwebhelper shim (mingw wrapper) | Reverted by Steam | Self-integrity check |
| Force GL4 core profile in winemac | ANGLE still GLES2, surface still 1×1 | Blocker is surface binding, not GL version |
| dwrite= override for Steam | `c0000135`, Steam won't boot | libcef hard-imports DWrite.dll |
| Prebuilt free wine-crossover | Gone | Gcenx pruned them; only upstream wine tracked now |
| HDR | No lever | Nothing to wire; don't fake it |

## Assets on disk (not shipped, kept)

`build/wine-crossover/wine-build/dist` (~1.5 GB): the complete from-source
CrossOver 26.2 wine build (boots, runs Steam, zero GPU crashes). Not used by
the shipping path — the Sikarugir matched pair supersedes it — but it's a
proven fallback and the BUILD-RESULTS.md there documents the toolchain.
