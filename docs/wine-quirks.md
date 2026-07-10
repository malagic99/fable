# Wine quirks — the fixes that make games run, and where to change them

Fable runs Windows games through Wine + D3DMetal on Apple Silicon under Rosetta.
That stack needs a pile of non-obvious workarounds — env vars, registry pokes,
launch flags, post-install repair. This file is the **map**: every quirk, the
symptom it fixes, and the one place to change it. It exists so debugging a
regression or upgrading the Wine build is a lookup, not an archaeology dig.

> Deep background — why the stack is shaped this way, the ABI law, the Steam
> CEF saga, and the closed dead ends — lives in [ARCHITECTURE.md](ARCHITECTURE.md).

> **Maintenance rule:** a quirk lives in exactly one place in code, documented
> at that place. If you find the same magic string in two files, centralize it
> (that's how `WineEnv` and `SteamPaths` came to be). When you add a fix, add a
> row here and a doc comment at the constant — not a bare literal at the call
> site.

## Where the fixes live

| Module | Owns |
|---|---|
| `Components/WineEnv.swift` | Every always-on Wine env var (AVX, msync debug, controllers, dialog-skip). One source of truth. |
| `Components/SteamPaths.swift` | The `Program Files (x86)/Steam/…` on-disk layout. |
| `Components/<Backend>Manager.swift` | Backend-specific renderer env (D3DMetal path, DXVK/DXMT overrides). Stays with the backend — it's not global. |
| `Components/PerformanceOptions.swift` | Frame-rate cap + MetalFX + Metal HUD env; the Rock Solid preset. |
| `Components/Stability.swift` | The "rubber mat" — game QoS + getting out of the game's way during play. |
| `ViewModels/ThermalMonitor.swift` | Detecting sustained throttling and nudging toward Rock Solid. |
| `Components/SteamInstallCommitter.swift` | Finishing WoW64-stalled Steam installs. |
| `Components/SteamRedistInstaller.swift` | Running Steam's bundled `_CommonRedist`. |
| `Components/AntiCheatDatabase.swift` + `ViewModels/QuirkService.swift` | Preemptive per-game quirks (anti-cheat verdicts now, ProtonDB next) surfaced in the compatibility banner *before* you install. Offline by default; online sources will need opt-in + caching. |
| `Components/GameDoctor.swift` | Fable Doctor — matching a game's log against known failure signatures and saying what to do. Data-driven rules; adding a diagnosis is adding one. |
| `Utilities/LogPruner.swift` | Capping runaway Wine logs. |

## The quirks

| Quirk | Symptom without it | Fix | Lives in | Memory |
|---|---|---|---|---|
| **AVX advertise** | Game CPU-checks AVX → int3 abort before rendering; looks like a graphics bug | `ROSETTA_ADVERTISE_AVX=1` on every launch | `WineEnv.advertiseAVX` | `rosetta-avx-flag` |
| **msync (downloads)** | Big Steam downloads spin IOCP at ~400% CPU, 0 Mbps under esync | `WINEMSYNC=1` (not esync) | `SikarugirManager.launchEnvironment` | `fable-msync-iocp-spin` |
| **msync log flood** | msync logs `err:server_register_wait` *per frame* → 25 GB log | `WINEDEBUG=fixme-all,-msync` everywhere | `WineEnv.debugDiagnostic` | `fable-msync-iocp-spin` |
| **Mono/Gecko dialogs** | Prefix creation blocks on installer UI | `WINEDLLOVERRIDES=mscoree,mshtml=` | `WineEnv.skipMonoGeckoDialogs` | — |
| **PlayStation pads** | DualSense/DS4 unrecognized by SDL games | `SDL_JOYSTICK_HIDAPI_PS4/PS5=1` | `WineEnv.playstationControllers` | — |
| **D3DMetal for Steam CEF** | Steam login renders a black square | `D3DMETAL_FRAMEWORK_PATH` + builtin override | `SikarugirManager.launchEnvironment` | `fable-d3d12-breakthrough`, `fable-winemac-drv-gap` |
| **Steam CEF flags** | Black/blank login window, dead QR | `-no-cef-sandbox -cef-disable-gpu-compositing -language english` | `BottleTemplateCatalog` steam template | `fable-cef-dwrite-trap` |
| **never disable dwrite** | `dwrite=` override → `c0000135`, Steam won't open | (don't) | `fable-cef-dwrite-trap` | `fable-cef-dwrite-trap` |
| **Steam install commit** | Download/extract finishes, install stalls at "installing files" (dead WoW64 service) | Move `downloading/`→`common/` + write manifest | `SteamInstallCommitter` | `fable-steam-install-wow64-gap` |
| **Steam bundled redists** | Game crashes on launch for missing `vcruntime140.dll` | Auto-run `_CommonRedist` vcredist/DirectX | `SteamRedistInstaller` | — |
| **Retina mode** | Steam CEF UI soft/pixelated (default 1× backing); but ON breaks non-HiDPI SDL games (corner render) | `RetinaMode`=y/n + `LogPixels`=192/96, per-bottle, default OFF | `WineManager.setRetinaMode` | `fable-retina-pixelation-fix` |
| **MetalFX + 60 fps cap** | AAA D3DMetal FPS decays over a session (unified-memory creep) | `D3DM_USE_METALFX_UPSCALER=1` + `D3DM_FRAME_RATE_LIMIT` | `PerformanceOptions` / recipes | `fable-current-state` |
| **GOG/Inno installers** | InnoSetup installer SIGKILLs WoW64 | Extract via bundled `innoextract`; quarantine xattr → SIGKILL | `GameInstaller` | `fable-wow64-gog-installers` |
| **runaway logs** | A spammy channel balloons one log to tens of GB | Per-file 200 MB + 500 MB total budget, skip active logs | `LogPruner` | `fable-msync-iocp-spin` |
| **mixed wineservers** | winetricks/installers fail `version mismatch NNN/NNN` while a game's (Sikarugir) wineserver holds the prefix — and vice-versa for launches after a helper ran | `PrefixRuntimeGate`: helpers call `gameLauncher.prepareExclusivePrefix(for:runtime:.off)` (refuses while games run, else drains foreign servers); `launchSmart` drains before starting a backend runtime. ANY new wine-spawning helper MUST call the gate | `PrefixRuntimeGate` + Doctor `wineserver-mismatch` | — |
| **.NET 6/7/8 apps** | "You must install .NET" / `hostfxr.dll not found` (e.g. VotV's YeetPatch = .NET 8) | Run MS's official windowsdesktop-runtime x64 exe in the bottle with `/install /quiet /norestart` — winetricks 20240105 has no dotnet8 verb. Verified: 8.0.28 installs clean on Wine Devel 11.10. `WineEnv.dotnetCoreOnWine` (USENLS + W^X, always-on) + mscoree NOT disabled are what make it run | manual / Run Installer + Doctor `dotnet-modern` | — |
| **WPF culture crash** | `.NET/WPF app crashes with CultureNotFoundException: 4096 (0x1000) is an invalid culture` before its window shows — ONLY on non-US-locale Macs (Wine writes keyboard Preload `00001000` when the host locale, e.g. en-DK, has no standard Windows LCID) | `WineManager.reconcileKeyboardLayout` rewrites the invalid `00001000` Preload → `00000409` (US) in user.reg; runs at prefix creation + idle-bottle heal on launch. NOT via env: USENLS crashes on 0x1000, INVARIANT then breaks WPF XAML — the registry layout is the only clean fix | `WineManager.keyboardLayoutRepaired` + Doctor `wpf-culture-4096` | — |
| **mscoree kills .NET Core** | With .NET installed, a Core app still fails `System.Runtime.dll: module not found` | Do NOT disable `mscoree` at launch — Wine's mscoree bootstraps IL. `WineEnv.base` skips only gecko (`mshtml=`); mono-dialog skip moved to `WineEnv.provisioning` (wineboot only) | `WineEnv.skipGeckoDialog` / `.provisioning` | — |
| **.NET Core ICU crash** | `Could not load ICU data. UErrorCode: 2` → every WPF/.NET-Core app crashes at start | `DOTNET_SYSTEM_GLOBALIZATION_USENLS=1` (use Wine's NLS, not .NET's bundled ICU) + `DOTNET_EnableWriteXorExecute=0` (JIT under Rosetta) — always-on, .NET-only | `WineEnv.dotnetCoreOnWine` | — |
| **.NET FRAMEWORK verbs are destructive** | winetricks `dotnet40/45/46x/47/48` return status 1 (`dotNetFx40_Full…exe` mscorsvw fails on WoW64) AND delete Wine Mono first → bottle left with NO .NET. Real casualty: EFT/SPT attempt, 2026-07-09 | DON'T install real MS .NET Framework on WoW64 wines — Wine Mono already provides 4.7/4.x. Repair a wrecked bottle: back up the stale MS `mscoree.dll` (system32+syswow64), `reg delete …\DllOverrides /v mscoree`, `reg add …\Wine /v Version /d win11`, `wineboot -u` → builtin mscoree loads shared `wine-mono-11.1.0`; verify `HKLM\…\NDP\v4\Full` Version | `WinetricksVerb.isDestructiveDotNet` (warns) + Doctor `dotnet` | — |
| **real .NET Framework needs 32-on-64** | WPF/.NET-Framework launchers (BSG Tarkov) crash in single-instance IPC on WoW64 wines; real MS .NET 4.8 won't install there | Use the **GPTK backend** — its `x86_32on64-unix` layer installs real .NET 4.8 to completion (proven: `NDP\v4\Full Release=528049`). Full ladder, install recipe, and the one missing component ("modern wine + 32-on-64") in [DOTNET-FRAMEWORK-LAUNCHERS.md](DOTNET-FRAMEWORK-LAUNCHERS.md) | GPTK backend + Doctor `mono-ipc-singleinstance` | — |

## Performance stability — the "rubber mat"

Steady FPS, not peak FPS. The levers, and which are real vs advisory:

| Lever | What it does | Lives in |
|---|---|---|
| **Game QoS** | Launch the game at `.userInteractive` → P-core priority over background work | `Stability.gameQoS` → `ProcessRunner.start` |
| **Get out of the way** | Skip the per-interval `ps` metrics sample while Fable is backgrounded (you're in-game); defer disk-usage tree walks while any game runs | `Stability.shouldSampleMetrics` / `.mayRunHeavyBackgroundWork` |
| **Rock Solid preset** | One click → 60 fps cap + MetalFX (where supported); a locked cap beats a flapping rate fighting vsync | `PerformanceOptions.rockSolid` |
| **Thermal nudge** | Detects the cool→throttling edge and nudges toward Rock Solid *while a game runs* | `ThermalMonitor` |

> **Hard constraint:** a running Wine game reads its frame cap from the env at
> launch — Fable can't re-cap a live process. So thermal handling is
> detect-and-advise (+ recommend a lower cap next launch), never silent live
> re-capping. Don't try to wire a dynamic cap to a running game; the channel
> doesn't exist.

## Known dead ends (don't re-attempt blindly)

- **Steam in-game overlay (Shift+Tab)** composites black — cross-process CEF
  GPU-shared-texture fails on D3DMetal. CrossOver-level Wine patch territory.
  Configure controllers from the main Steam window instead. (`fable-steam-overlay-diagnosis`)
- **Protected/packed exes** (certain Denuvo/repack int3 fail-fasts) abort
  identically on *every* backend including CrossOver — not a Fable bug.
  (`fable-d3d12-breakthrough`)

## Adding or changing a quirk

1. Put the value at its owning module (above), with a doc comment: symptom →
   fix → verification date.
2. If it's an always-on Wine env var, it belongs in `WineEnv`; a Steam path, in
   `SteamPaths`; a backend renderer var, in that backend's manager.
3. Add a row to the table here and, if it's a deep/non-obvious finding, a
   memory note — then link it from `MEMORY.md`.
4. Lock it with a test (see `WineEnvTests`, `SteamPathsTests`) so an upgrade
   can't silently drop it.
