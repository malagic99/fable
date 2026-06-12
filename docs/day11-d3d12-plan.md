# Day 11 plan: D3D12 support via Game Porting Toolkit (D3DMetal)

Goal: run D3D12-only games (UE5 era — STALKER 2, etc.) by integrating
Apple's D3DMetal translation layer as a third runtime component
alongside Wine and DXMT.

## What D3DMetal is

Apple's Game Porting Toolkit (GPTK) ships `D3DMetal.framework` plus
Wine-side shim DLLs (`d3d12.dll`, and its own `d3d11`/`d3d10`/`dxgi`
variants). Unlike DXMT (open source, redistributable), **GPTK's license
does not permit redistribution** — users must download it themselves
from Apple (requires a free developer account).

## Integration design

1. **Component, but user-supplied.** New `gptk` component that cannot
   be auto-downloaded. UI: Components tab row with "Import from
   GPTK .dmg…" — user downloads `Game_Porting_Toolkit_*.dmg` from
   developer.apple.com; Fable mounts it (`hdiutil attach`), copies
   `lib/` payload into `Components/gptk/<version>/`, detaches. Show
   clear guidance + link, mirroring how we already guide Gatekeeper.
2. **File placement (mirrors DXMTManager):**
   - `D3DMetal.framework` + `libd3dshared.dylib` → Wine's
     `lib/external/` (next to `lib/wine`)
   - GPTK's PE DLLs (`d3d12.dll` etc., from `lib/wine/x86_64-windows/`)
     → bottle `system32`
3. **Per-bottle graphics backend picker** replaces the single DXMT
   toggle: `Off / DXMT (D3D11) / GPTK (D3D9–12)`, persisted as an enum
   in bottle.json (migrate `dxmtEnabled: true` → `.dxmt`).
   - DXMT mode: overrides as today.
   - GPTK mode: `WINEDLLOVERRIDES` routes `d3d9,d3d10,d3d11,d3d12,dxgi=n`
     to GPTK's DLLs; env `D3DM_SUPPORT_DXR=1` optional for ray tracing;
     `WINEDLLPATH`/`DYLD` handled by Wine's external lib lookup.
4. **Wine build compatibility risk (research first):** GPTK's D3DMetal
   is built against Apple's GPTK Wine fork. Community evidence
   (Whisky, Heroic's gptk toolkit, CXPatcher) shows it works on
   Gcenx-style builds when the external lib path is set, but version
   pairs matter. Test matrix: wine-stable 11.0_1 + GPTK 3.x on a
   throwaway bottle before wiring UI.
5. **Detection/UX:** when a launch log shows
   `D3DERR`/`d3d12 not found` with backend Off/DXMT, toast a hint to
   switch the bottle to GPTK.

## Order of work

1. `hdiutil` import flow (ProcessRunner; mount → copy → detach) + tests
   with a fixture dmg built by `hdiutil create`.
2. `GPTKManager` (placement + overrides), modeled on DXMTManager.
3. Backend enum migration + Graphics section picker UI.
4. Manual verification: a D3D12 title the user owns via Heroic
   (STALKER 2 Windows build, link-without-copy import — the symlink
   mode added on dev exists precisely for this).
5. README + About credits update (GPTK license constraints documented).

## Open questions

- Heroic already has `game-porting-toolkit` in
  `~/Library/Application Support/heroic/tools/` — offer to import from
  there when present (zero-download path, same trick as the wine
  pre-seed).
- 32-bit D3D9 games under GPTK: GPTK is x86_64-only; keep DXMT/builtin
  for 32-bit titles.
- esync/msync env flags (`WINEESYNC=1`/`WINEMSYNC=1`) measurably help
  UE5 titles — consider exposing as bottle-level performance toggles
  the same day.
