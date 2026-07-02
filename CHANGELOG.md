# Changelog

## v0.10.0 — 2026-07-02

Two faces, your pick: the new **Gamer** interface joins Classic, chosen on
first launch and switchable any time.

### The Gamer interface — games first

- **Cover wall**: every game across every bottle as covers. Single-click to
  inspect, double-click to play. Search built in.
- **Confidence dots** on every cover — will it run, before you click:
  green = a verified recipe matches, amber = known caveats, red = anti-cheat
  won't run under Wine, gray = honestly untested. Powered by the recipe
  catalogs + the quirk system's anti-cheat database.
- **Inspector**: how the selected game runs — health, backend, frame cap,
  MetalFX, and its adaptive-trigger L2/R2 profile — with Play and Tune right
  there. You play and tune without ever thinking about bottles.
- **Workshop**: the complete Classic app, one rail-click away. Nothing was
  removed — bottles, components, settings, and all tools live there.
- **Now playing** appears in the rail while a game runs.

### Choosing

- New **onboarding step**: pick Classic or Gamer as your default on first
  launch, with sketch previews of each.
- **Settings → Interface → Style** switches live, any time, both directions.
- Existing setups keep Classic — nothing changes until you choose.

## v0.9.0 — 2026-07-02

UI redesign: fluid, clean, balanced. Reviewed live on screen, then rebuilt
around one design language (`FableTheme`).

### The bottle page is games-first now

- **Hero header**: cover art, the bottle's name in large type, status +
  backend chips, quick facts (Windows · games · size), and a prominent Play —
  the one thing you actually do with a bottle. The wall of metadata that used
  to sit above your games moved to a "Details" section at the bottom
  (advanced mode).
- The settings column is width-capped and centered so it no longer floats in
  a void on large windows.

### One card language

- Bottle and Library tiles share one roomier card: bigger cover art, clearer
  title, dot-separated quick facts, springier hover lift with a subtle glow.
- **Backend badges stopped shouting.** Sikarugir was alarm-pink on every card —
  red tones now mean actual problems; backends get quiet informative tints
  (Sikarugir is indigo, matching the app's identity).
- A dashed **New Bottle** tile joins the grid, so a sparse library reads as an
  invitation instead of a void.

### Identity

- The wineglass-on-gradient mark (previously onboarding-only) now heads the
  sidebar — the app carries its own identity.
- `FableTheme` centralizes the gradient, card surface, and backend tints;
  one shared `ExeIconView` replaced three copy-pasted icon loaders.

## v0.8.1 — 2026-07-02

Backend surgery: one launch flow, a tested routing core, two trigger fixes.
No user-facing behavior changes beyond the fixes.

### Under the hood

- **One launch flow.** The Play/Stop logic that was copy-pasted across three
  controls (Library, grid quick-launch, game rows) now lives in one place —
  `GameLauncher.launchSmart`/`stopSmart`, with the launcher's collaborators
  wired once at startup. The Steam-prerequisite nudge now fires consistently
  from every Play control (it was Library-only), and it no longer false-fires
  in the window right after Fable itself started Steam.
- **The launch-routing core is now tested.** Backend → wine binary / runtime
  key / wineserver-drain, plus the environment layering (base → backend →
  performance → per-game wins) were the most load-bearing untested lines in the
  app. `composeLaunchPlan` gained a runtime-resolution seam and 10 tests lock
  the whole table.

### Fixes

- **Closing the trigger config sheet no longer kills a running game's trigger
  profile** — the config panel previews without disturbing the session-applied
  profile, and restores it on close.
- **Honest label on per-game trigger overrides**: they apply when a game is
  launched from Fable; a game started from inside Steam keeps the bottle
  default (that's a Wine-boundary constraint, now stated in the UI instead of
  silently surprising you).

## v0.8.0 — 2026-07-01

Two controller/setup features.

### DualSense adaptive triggers

- Set a **static adaptive-trigger feel per bottle** — a resistance wall
  (weapon), constant tension (feedback), or a buzz (vibration) on L2/R2 — with a
  **per-game override**. Presets (Shooter, Racing, Heavy) get you started, and
  the config panel **previews live** on the pad as you drag a slider. Applied
  when a game launches, cleared when it exits. Validated on hardware over USB and
  Bluetooth.
- Honest scope: these are static profiles you set (like Steam Input's trigger
  config) — a Wine game's *own* contextual trigger effects can't cross the Wine
  boundary.

### D3DMetal set-up in the first-run wizard

- New **mandatory graphics step** in onboarding: detects Apple's D3DMetal (via
  the free Sikarugir), shows its version, and offers **one-click set-up** — or
  guides installing Sikarugir when it's missing. Makes the flagship backend
  (Steam + D3D12) work out of the box for a new user, with an informed "continue
  without it" escape for those who only want older D3D9 games.
- **Sikarugir updates** are now detected and applied (it was install-once);
  a newer engine on disk shows an "Update" action.

## v0.7.1 — 2026-07-01

Accurate Play/Stop state — Fable now knows what's *actually* running.

### Fixes

- **Real running detection.** Fable used to only know about games it launched
  itself, so state was wrong in two common cases. It now scans the process table:
  - A game launched **from inside Steam** shows as running.
  - A process that **lingers after its window closes** is reflected correctly —
    no more stale "running" that never clears (and no more Steam appearing idle
    while a game runs, or vice-versa).
- **Stop actually stops it.** For a game Fable didn't launch (or a lingering
  one), Stop now falls back to killing the bottle's wine tree instead of doing
  nothing.
- **Steam prerequisite nudge.** Launching a Steam game (under
  `steamapps/common`) while the Steam client isn't running now shows a clear
  "start Steam first, then launch it from your Steam library" message instead of
  a cryptic failure.

## v0.7.0 — 2026-06-29

Shader cache management. (Version is just "where we stand" — the publication/
distribution track is parked; Fable is a polished personal tool.)

### New — durable, offloadable shader cache

- **Shaders survive a reboot now.** D3DMetal compiles its Metal pipelines during
  play — the reason a game smooths out after its first hour — but those live in
  macOS's volatile darwin cache, which a reboot/cleanup purges (bringing the
  first-run stutter back). Fable now keeps a durable copy and **restores it
  automatically at startup** when the live cache was purged.
- **Offload to external storage.** Settings → Shader Cache shows the saved size
  and lets you back the cache up to an external drive to reclaim local space,
  then bring it back on demand.
- Automatic snapshot after each session + auto-restore at startup; manual
  back-up / bring-back in Settings.

### Honest scope

- Metal compiles shaders on-demand during play — there's **no pre-build**
  (no Fossilize/Steam-precache equivalent), so the cache fills as you play and
  pays off from the second run on.
- Unlike Proton's portable per-game `.dxvk-cache`, the D3DMetal cache is Apple's
  per-app Metal cache; Fable manages it per-machine for the backend, never
  touching Apple/system or the shared global Metal cache.

## v0.6.1 — 2026-06-27

Bug-fix pass from real-world testing (Ready or Not running flawlessly — fans
near-silent and temps barely above room after the first hour).

### Fixes

- **A failed winetricks verb no longer destroys the bottle.** Bottle creation
  used to abort *and self-delete* if any verb failed — so a `corefonts` download
  hitting a dead SourceForge mirror nuked the whole bottle on every retry. Verbs
  are now best-effort: a failure is recorded and surfaced ("retry from the
  bottle's Winetricks button"), and the bottle is still created.
- **Wine drive self-heal.** Fable now ensures the standard `C:` → `drive_c` and
  `Z:` → `/` mappings exist before every launch (and on prefix creation). Fixes
  the "Wine keeps looking for the Z: drive it can't find" failure when running an
  exe or installer located anywhere outside `C:`.

### New

- **"Winetricks…" button** in a bottle's Wine Tools, next to Wine Settings —
  browse/install runtimes, fonts, and components, and retry anything that didn't
  finish during setup.

## v0.6.0 — 2026-06-27

The big one. Free Steam doesn't just render now — it **installs and plays AAA
games end to end**, your whole library lives in one place, the app picks the
right backend and holds a steady frame rate on its own, and it tells you what's
wrong when something breaks. This release rolls up the "bulletproof installs"
(v0.5) and "your whole library" (v0.6) milestones.

### Headline — free Steam that installs *and* plays AAA games

- **Steam installs end to end.** `WINEMSYNC=1` kills the IOCP syscall spin that
  throttled big downloads to ~0 Mbps; `SteamInstallCommitter` finishes installs
  stalled on the dead-WoW64 commit step (auto-heals on bottle open and on Steam
  exit); and Fable now auto-runs the VC++/DirectX redistributables Steam unpacks
  into `_CommonRedist` but never executes — no more missing-`vcruntime140.dll`
  crashes on first launch.
- **DEATHLOOP (30 GB D3D12 AAA) runs stable**, validating the whole chain.

### Library + import

- **Library view** — every game across every bottle in one searchable grid,
  one click to play, cover art from the game's own icon.
- **Import from Heroic** — pulls installed Epic / GOG / Amazon games into a
  bottle (symlinked, no copy), filtering out uninstalled, mac-native, and
  redistributable entries.

### Smart Bottle gets smarter

- **Auto backend pick** — an untouched bottle picks the right backend the first
  time you press Play (validated recipe, or modern-D3D compatibility markers).
- **Quirk system** — preemptive per-game verdicts in the compatibility banner:
  the offline **anti-cheat database** (Apex/Valorant/etc. flag "won't run on
  Wine" by name, pre-install) and **ProtonDB** community ratings (opt-in,
  cached, off by default — it sends a Steam app ID to a third party).
- **Shareable recipes** — export a tuned game as a `.fablerecipe`; import one
  and it overrides the built-in catalog so the setup auto-applies.

### Stability + diagnostics

- **The "rubber mat"** — games launch at high QoS (performance cores), Fable
  gets out of the way during play (no `ps` sampling while you're in-game, no
  disk walks mid-session), a one-click **Rock Solid** preset (60 fps cap +
  MetalFX), and a thermal nudge when the Mac starts throttling.
- **Fable Doctor** — "Diagnose Last Run…" reads a game's Wine log and explains
  what went wrong (missing runtime, anti-cheat, backend mismatch) in plain
  language.
- **Controller support** (PlayStation DualSense / DualShock 4) and runaway-log
  protection (the msync flood that wrote 25 GB logs is silenced; a pruner caps
  the rest).

### Under the hood

- **Agent-maintainable core** — the scattered Wine env fixes and Steam paths are
  centralized in `WineEnv` / `SteamPaths`, every quirk mapped in
  `docs/wine-quirks.md` with its rationale and how to change it.
- ~280 tests across ~68 suites, all passing.

### Known limitations

- Distribution is still the gate to 1.0: builds aren't yet notarized/signed
  (needs an Apple Developer ID), so first launch needs right-click → Open.
- HDR output isn't exposed — a running Wine game's Metal layer is owned by
  D3DMetal in the subprocess, with no Fable-side lever to force it.
- Kernel anti-cheat games (EAC/BattlEye/Vanguard) can't run under any macOS
  Wine; the quirk system now flags them up front instead of letting you find
  out the hard way.

## v0.4.1 — 2026-06-15

Compatibility release. Headline is a free fix that unblocks a whole
class of games, plus the Sikarugir D3D12 backend and the DXVK/vkd3d
correction.

### Headline — the AVX free fix

- **`ROSETTA_ADVERTISE_AVX=1` is now set on every launch.** Default
  Rosetta 2 advertises only SSE4.2 to translated x86 games (AVX=0,
  AVX2=0, FMA=0, BMI2=0). Many 2020+ titles run a CPU-feature check at
  startup and deliberately abort (int3) if AVX/AVX2 is missing — an
  invisible failure that looks like a graphics/Wine bug but is the CPU
  gate. This single env var flips AVX/AVX2/FMA/BMI2 on (verified on
  macOS 26.5 / M4 Pro). CrossOver and GPTK do this internally; Fable now
  matches them, for free, across every backend. No-op on native-arm64
  Wine.

### New backend

- **Sikarugir backend** — discovers a local Sikarugir install, extracts
  its GPL wine-10.0 engine into Fable's components, and overlays the
  d3dmetal renderer (D3DMetal recompiled against modern Wine). This is
  the free matched-pair recipe — modern SEH + real D3D12→Metal — that
  Apple's wine-7.7 GPTK can't provide. Architecture verified identical
  to CrossOver 26.2's commercial implementation.

### Fixes

- **DXVK backend now installs vkd3d-proton for D3D12.** DXVK only does
  D3D9/10/11; D3D12→Vulkan is the separate vkd3d-proton project. The
  backend's DLL routing now includes `d3d12core` (vkd3d 3.x split it
  out) and the display name names vkd3d explicitly.

### Notes

- 174 tests across 47 suites, all passing.
- Known limitation surfaced this cycle: games with packed/protected
  exes whose anti-tamper rejects the emulated environment (e.g. certain
  cracked repacks) abort identically on every backend including
  CrossOver — no wrapper fixes those; use a clean release or stream from
  a Windows PC. Smart Bottle's heuristics flag the telltale signs.

## v0.4.0 — 2026-06-14

Pushed past the Wine 7.7 ceiling. New backends, Smart Bottle
compatibility scanner, and the Info.plist version finally matches the
binary (v0.1.0 had been shown in Settings since the initial sprint).

### Headline

- **Two new graphics backends** that bypass GPTK's wine-7.7 SEH wall:
  - `dxvk` — D3D11/12 → Vulkan → MoltenVK → Metal on Wine Devel
    11.10. Loses D3DMetal's optimization but supports modern Wine
    SEH that GPTK fails on (the 007 First Light int3 wall).
  - `crossover` — routes through the user's installed CrossOver.
    Modern wine + Apple-licensed D3DMetal in one stack. Auto-detected
    at `/Applications/CrossOver.app`.
- **Smart Bottle** — `CompatibilityScanner` walks game install dirs
  and flags Streamline, DirectStorage, EAC/BattlEye/Vanguard, Goldberg
  with missing `steam_interfaces.txt`, repack tokens, Denuvo. Inline
  expandable banner under each game with severity + suggestion, plus
  a "💡 Try DXVK" / "Try CrossOver" recommendation chip when a better
  backend is detected.
- **First-launch wizard** (Day 21, was Stage B1 — pulled forward).
  Welcome → Source (Steam / Heroic-GOG-Epic / Manual) → First bottle
  from a template → Done. Re-runnable from Settings.

### Backends & runtime

- `GraphicsBackend` enum gains `.dxvk` and `.crossover` cases with
  backward-compat JSON decoding for v0.3.0 bottles.
- `GameLauncher.launch()` routes each new backend with its own wine
  binary + env; runtimeKey separates them in the multi-runtime
  conflict check.
- `CrossOverManager` discovers CrossOver across 23/24/25 path layouts.
- `DXVKManager` provides launch env (`WINEDLLOVERRIDES=…=n`,
  `DXVK_FRAME_RATE`, `DXVK_LOG_PATH`) and a prefix-presence check.
- `CompatibilityRuntime.discover()` order: CrossOver → WhiskyWine →
  Heroic GPTK → Fable's GPTK. Reversed from v0.2.0 because CrossOver
  has the WoW64 stack patches the others lack.
- `GPTKManager.overlayEvaluationLibraries` now strips
  `com.apple.quarantine` after merging the dmg payload. Without this
  Wine running under Rosetta failed `dlopen("D3DMetal")` with
  `STATUS_DLL_INIT_FAILED`.

### Onboarding & UX

- First-launch wizard surface (`OnboardingState` + `OnboardingView`).
- SwiftUI's `Text`/`Label`/`Button` localization now actually works —
  `make-app.sh` mirrors `.lproj` resources into `Fable.app/Contents/
  Resources` and stamps `CFBundleLocalizations`. v0.3.0 ad-hoc builds
  showed raw keys like `sidebar.bottles`.

### Tests

159 tests across 44 suites, all passing.

### Known limitations

- DXVK still has to be installed once per bottle via `winetricks dxvk`
  — automation slated for a v0.4.x patch.
- CrossOver detection assumes default `/Applications/CrossOver.app`
  install path; non-standard locations aren't supported yet.
- 007 First Light still doesn't run because of platform-level
  Streamline + Goldberg limitations — not a Fable bug, but Smart
  Bottle now surfaces the cause pre-launch.

## v0.3.0 — 2026-06-13

First-launch experience + foundations for bottle export/import +
critical localization fix. Test build cut off `dev` HEAD so users can
exercise the new wizard + Steam install flow in the real world.

### Headline

- **First-launch wizard.** Four-step flow on first open: Welcome →
  Where are your games? (Steam / Heroic-GOG-Epic / Manual) → Create
  your first bottle (pre-fills the template based on your source) →
  You're all set. Localized in English + Spanish; re-runnable from
  Settings → About.
- **CrossOver wins for 32-bit installers** by default now. The
  `CompatibilityRuntime.discover()` order was backwards in v0.2.0 —
  preferred Fable's bundled GPTK (wine 7.7 base, no WoW64 patches)
  over CrossOver (which has years of macOS-specific patches). Reordered:
  CrossOver → WhiskyWine → Heroic GPTK → Fable GPTK. Substantially
  improves the success rate on ISDone/FreeArc-packed installers.
- **Localization actually works now.** SwiftUI's `Text("foo")` /
  `Label("foo", systemImage:)` / `Button("foo", action:)` auto-resolve
  via `Bundle.main`, but v0.2.0 only put the .strings files in the
  SwiftPM resource bundle — every key rendered raw (you'd see
  "sidebar.bottles" instead of "Bottles"). `make-app.sh` now mirrors
  `.lproj` dirs into the app's main Resources and stamps
  CFBundleLocalizations. Affects every translated string in the app.

### Foundations

- **`BottleArchive` utility** — packs a bottle + prefix + manifest
  into a tar+zstd `.fbottle` archive; `inspect()` reads just the
  manifest; `unpack()` validates schema version and prefix SHA-256.
  No UI yet — that lands in v0.3.1 (export button) and v0.3.2
  (drop-to-import). Use case: install in CrossOver where WoW64 works,
  export, import into Fable for everyday play.
- **Roadmap docs** — `docs/roadmap-tier-1-3.md` (Days 21–58 day-by-day,
  three planned releases v0.3 → v0.5) and `docs/roadmap-tier-4-plus.md`
  (gate-driven stages A–F up to v1.0.0). Both include a model-swap
  protocol so session changes don't lose context.

### Bug fixes

- Onboarding **Done step never showed** — `advance()` to `.done`
  flipped `hasCompleted`, which dismissed the sheet before the user
  saw "You're all set". Now only the Start Playing button completes
  the flow.
- Runtime-built `LocalizedStringKey("foo.\(x)")` strings rendered raw
  (only literal-built keys auto-resolved). Routed through `L10n.string()`
  for the source-picker cards specifically.

### Tests

129 tests across 39 suites, all passing.

### Known limitations

- BottleArchive is utility-only; no Export/Import UI yet (Day 23/24).
- Update flow still points users at the release page — no in-place
  install until an Apple Developer ID lands.
- Apple GPTK fallback (when no CrossOver installed) still hits the
  WoW64 bug on certain installer classes — a Wine-upstream issue, not
  fixable from Fable.

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
