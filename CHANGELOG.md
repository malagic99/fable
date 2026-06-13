# Changelog

## v0.2.0 — 2026-06-13

The "post-sprint roadmap" release. Closes items 7–15 of the original
1–15 backlog plus the wine-devel 11.10 upgrade and the Day 12
performance toggles.

### Headline

- **D3D12 via Apple's Game Porting Toolkit.** Pick a per-bottle graphics
  backend (`Off` / `DXMT` / `GPTK`). GPTK Wine is wine-devel 11.10 with
  D3DMetal 4.0 beta 1 overlaid from Apple's evaluation environment dmg —
  importable through Settings → Components.
- **Steam in one click.** "New Steam Bottle…" provisions the prefix,
  installs vcredist + corefonts, runs the upstream winetricks `steam`
  verb (which downloads Steam itself), and registers `Steam.exe` with
  the documented `-no-cef-sandbox` workaround.
- **Winetricks integration.** 500+ verbs browsable via "More from
  Winetricks…" in each bottle's Dependencies section. Single-script
  install with pinned sha256.
- **Wine upgraded to 11.10.** Both the standard Wine component and the
  GPTK backend now run wine-devel 11.10 (previously stable 11.0_1 / GPTK
  3.0-3's wine-7.7).

### Bottles

- Bottle templates with curated presets: Vanilla, Classic Games (D3D9),
  Modern Games (DXMT), Steam Ready, Cutting Edge (GPTK / D3D12). Each
  carries dependencies, winetricks verbs, and auto-registered games.
- "Duplicate Bottle" toolbar action — recursive prefix copy + reset
  identity. Refuses while games run in the source.
- Per-game graphics backend override — a D3D9 game and a D3D11 game can
  now share a bottle without fighting over the toggle.

### Performance

- Per-bottle performance toggles surfaced in `BottleDetailView`:
  - Metal Performance HUD (`MTL_HUD_ENABLED=1`)
  - MetalFX Upscaling (`D3DM_USE_METALFX_UPSCALER=1`, GPTK only)
  - Frame-rate cap — backend-agnostic, routes through DXMT_CONFIG or
    D3DM_FRAME_RATE_LIMIT depending on the active backend
- Live CPU% + resident memory per running game, sampled every 2 s via a
  `ps` process-tree walk.

### Storage & troubleshooting

- Disk-usage display per bottle (card footer + Storage section in detail
  view). Cached, scanned lazily on first appearance.
- "Clean Wine Temp Files…" — wipes `drive_c/windows/Temp` and each
  user's Temp/AppData/Local/Temp.
- "Force Kill Wine Processes…" — runs `wineserver -k` against the
  prefix, the escape hatch for hung games where Stop doesn't take.

### App

- In-app update checker polls GitHub releases for newer Fable builds
  (debounced once per hour). Banner offers Open Release Page / Skip
  This Version / Dismiss. Manual check from Settings → About.
- Localization scaffold: `defaultLocalization: "en"`, processed
  `en.lproj`/`es.lproj` resources, an `L10n` helper for non-View
  strings, and a real Spanish seed translation for the highest-traffic
  ~30 keys.

### Tests

114 tests across 37 suites, all passing.

### Known limitations

- Update flow points users at the release page; in-place updates need
  an Apple Developer ID + Sparkle (deferred until that's available).
- First Light installer still crashes the GPTK path at
  `alloc_pages_vprot`. The wine-11.10 upgrade did not fix it — needs a
  newer Wine base inside Apple's GPTK itself.

## v0.1.0 — 2026-06-12

Initial 10-day sprint release. Wine bottle management, DXMT 0.80 for
D3D11→Metal, dependency catalog (vcredist/OpenAL/DirectX), GOG/Inno
installer extraction via bundled innoextract, settings + config.json,
release packaging.
