# SteaMac (FX Steam Launcher) vs Fable

Research note, 2026-11-24. Read-only: nothing from SteaMac was built or run.

**Sources:**
- Site: https://fxgl.github.io/steamac/
- Repo: https://github.com/fxgl/steamac, shallow clone at commit `79aeadb` (2026-11-16). Paths below are relative to that repo.
- Fable: `main` at `83ea4a7` (v1.3.10).

---

## TL;DR

- **SteaMac is not a Wine launcher.** It boots Valve's own **ARM64 SteamOS** in a libkrun/Hypervisor.framework VM. Steam is the native Linux ARM64 client, and games run through Valve's Proton 11 (ARM64) with FEX for x86. Graphics go DXVK/vkd3d-proton → Mesa Venus (guest) → virglrenderer → MoltenVK or KosmicKrisp → Metal (host).
- **Their fix for the Steam black window is to avoid Windows Steam entirely.** There is no CEF flag, `steamwebhelper` patch or `-noverifyfiles` anywhere in the repo, because Steam never runs under Wine. Fable's version of this idea is the native Steam bridge (`docs/NATIVE-STEAM-BRIDGE.md`), not anything copyable from SteaMac.
- **The most useful thing to take is their patched DXMT.** `host/dxmt/patches/` holds 23 functional commits on upstream `3Shain/dxmt` main. They are crash and hang fixes cherry-picked from about 8 forks (each reviewed in a ledger), plus useful `DXMT_CONFIG` options: `dxgi.maxFrameLatency`, `dxgi.customVideoMemory` and `d3d11.submitBeforePresent`. Fable ships stock DXMT v0.80 (April 2026). The licence is LGPL-2.1-or-later, so it is compatible with Fable.
- **Second, how they edit Steam's config.** They edit it only while Steam is stopped, preserve every byte they don't change, let a user's edit win, and record what they wrote so they can undo it. They also gate per-title defaults on what the device can actually do (`guest/layer/usr/lib/steamac/steam-title-defaults`).
- **Side finding (Fable bug):** `THIRD-PARTY-NOTICES.md:37` lists DXMT as **zlib**. Upstream `3Shain/dxmt/LICENSE` today says **LGPL-2.1-or-later**; the zlib text survives only as `LICENSE.OLD`. Fable downloads DXMT at runtime rather than redistributing it, so the impact is small, but the notice is wrong.

---

## 1. What SteaMac is and how it works

### Architecture
README and site; `host/launcher/Sources/steamac-vm/VM.swift` and `Supervisor.swift`.

| Layer | What it uses |
|---|---|
| Hypervisor | libkrun on Hypervisor.framework, patched in `host/libkrun/patches/` (25 patches: virtio-gpu blob alignment, CoreAudio virtio-snd, runtime display resize, `krun_pause`, GPU activity counters, QoS) |
| Guest OS | Valve's SteamOS for ARM64 (the Steam Frame build). It is downloaded from Valve as a **signed RAUC bundle**, and the CMS signature is checked against Valve's pinned CA only (`RaucBundle.swift`, `scripts/keys/`). The root filesystem is not modified; their additions are an initramfs plus a read-only layer (`guest/layer/`). |
| Guest kernel | Patched (`guest/kernel/patches/`), including **Apple hardware TSO** via `PR_SET_MEM_MODEL` (0002–0005) so FEX can skip its memory-ordering emulation |
| CPU | Steam is native ARM64. Games run in Proton 11 ARM64 with FEX for x86-64, or in Proton 10 x86-64 under FEX for the DXMT path. |
| D3D9/10/11 | DXVK (inside Proton) → Vulkan |
| D3D12 | vkd3d-proton → Vulkan. Feature level 12_0 on KosmicKrisp and 11_0 on MoltenVK; SM 6.0. UE5 titles that need 12_1 or SM 6.6 fail. |
| Vulkan, guest | Mesa Venus (`guest/mesa/patches/`) |
| Vulkan, host | virglrenderer (23 patches) → **MoltenVK** (UTM fork plus patches, macOS 15+) or **KosmicKrisp** (Mesa's Vulkan-on-Metal-4 driver, macOS 26+, **~100 patches** in `host/kosmickrisp/patches/` adding geometry shaders, transform feedback, sparse residency, 64-bit atomics and a pipeline cache) |
| DXMT (opt-in) | `wmtr/` remotes DXMT's Metal calls from the guest to a host library (`libwmtr_host.dylib`), using DXMT source patched in `host/dxmt/patches/`. Off by default; it explicitly lets guest code run on the Mac with the user's rights. |
| GPTK / D3DMetal / CrossOver | **Not used at all.** |
| Audio / input | virtio-snd → CoreAudio. GameController.framework pads are re-created as uinput/uhid virtual pads (Xbox, DualSense, DS4) for Steam Input. Keyboard and mouse go through virtio-input. |

### How Steam is installed and run
- Steam ships with SteamOS. The launcher picks the client branch from `--steam-client frame|deck|deckbeta`, which ends up in a kernel cmdline value. `guest/layer/usr/lib/steamac/steam-client` writes it to `~/.local/share/Steam/package/beta` and removes the Frame-only `-deckard`/`-vrgamepadui` lines from a copy of Valve's `RUNSTEAM.sh`; it never edits the original. If the expected lines aren't there it refuses to guess and falls back to stock (lines 107–115).
- On first sign-in it uses the Deck client so the QR login works, then restarts Steam once an account is remembered (`steam-client --watch`, lines 23–39).
- A set of `ExecStartPre` hooks edits Steam's config before every start (`guest/layer/usr/lib/systemd/user/steam.service.d/50-steamac.conf`). See §2.

### Packaging, signing, updates
- DMG on GitHub Releases. Developer ID signed, hardened runtime, notarized and stapled for both app and DMG (`host/launcher/dist.sh`).
- **Sparkle 2** with an EdDSA-signed appcast at `docs/appcast.xml` (`SparkleUpdates.swift`, `appcast.sh`). Builds that can't replace themselves (translocated, read-only volume, source builds) fall back to the GitHub releases API with an ETag and a 6-hour throttle (`UpdateCheck.swift:5-25`).
- Crash reports go to their **Sentry, on by default** with an opt-out (`CrashReporting.swift`, 2,112 lines). "Report a Problem" uploads a log bundle; the bundle is first collected into a folder the user can inspect (`Report.swift:8-13`).
- Opt-in anonymous **game statistics** go to a Cloudflare Worker (`services/game-stats/`) and feed a public compatibility page (`docs/games.html`; `GameStats.swift:8-19`).

### Licence
**Apache-2.0** for the project (`LICENSE`, `NOTICE`), with these exceptions per `NOTICE`:
- kernel patches and config: GPL-2.0-only
- Mesa and virglrenderer patches: MIT
- files derived from Valve's deckard session: MIT
- DXMT and the DXMT patches: LGPL-2.1-or-later. GPL sources are shipped as a tarball attached to each release.

---

## 2. What SteaMac does that Fable doesn't

### Steam integration
1. **Native ARM64 Steam client.** This is why CEF, the black square, `steamwebhelper` and `-no-cef-sandbox` simply never come up for them. Fable's equivalent fixes live in `BottleTemplateCatalog.swift:95-117` and `Sikarugir11Manager.swift:337-346`.
2. **Byte-preserving config edits while Steam is stopped.** Every hook has a tokenising VDF reader that records spans and writes back only the changed bytes. Writes are atomic (`mkstemp` + `os.replace`) and keep the original file mode (`steam-idle-screensaver:268-343`, the same helpers in `steam-title-defaults` and `steam-compat-default`). Fable's `SteamKeyValues.swift` parses into a tree and re-serialises it, which is fine for `.acf` files but riskier for `config.vdf` and `localconfig.vdf`.
3. **"User edit wins" ownership model.** `steam-title-defaults:401-406` remembers per account what it last wrote (`~/.config/steamac/title-defaults.json`). If Steam's stored value has changed since, it treats that as a user edit and stops touching that key for good. When a capability disappears, it restores the previous value. `steam-compat-default` applies the same rule to per-game compatibility-tool mappings (priority 250, never the `"0"` wildcard; the docstring explains how a wildcard once broke FEX).
4. **Per-title defaults gated on real device capability.** Dragon's Dogma 2 gets `VKD3D_FEATURE_LEVEL=12_1 VKD3D_SHADER_MODEL=6_6`, but only if `vulkaninfo` reports `shaderBufferInt64Atomics`/`shaderImageInt64Atomics` (`steam-title-defaults:420-425`, and the `device_features()` probe bounded by `timeout 10`).
5. **Steam setting defaults applied once, with a marker file.** Background Vulkan shader processing is switched on (`steam-shader-defaults`). Steam's idle screensaver is switched off (`IdleScreensaverACSeconds`/`IdleScreensaverBatterySeconds` = 0), because it stole focus from games on long load screens (`steam-idle-screensaver`).
6. **VRAM reporting matched to a unified-memory budget.** `VK_VRAM_REPORT_LIMIT_HEAP_SIZE` is set from the launcher's GPU budget instead of a fixed 4 GiB (`steam-gfx-env`).
7. **Shared Mac folder registered as a Steam library** (`steam-share-library`, virtio-fs).

### Graphics and performance
8. **Patched DXMT.** 23 functional commits, each with an origin and a verdict in the ledger inside `host/dxmt/patches/0024-*.patch`:
   - **Fixes:** NSError over-release across the boundary (#8/#9); compiler-worker teardown (#10–#12, with regression tests); dropping draws and dispatches whose pipeline failed to compile instead of crashing (#6/#7); an occlusion-query hang (#4); `UpdateSubresource` into STAGING aborting (#5); Direct2D interop via `IDXGISurface` and `SwapDeviceContextState` (#13/#14); `SO_STATISTICS` queries, which World of Tanks needs (#15); a command-slot race (#19).
   - **Options:** `dxgi.maxFrameLatency` (#3), `dxgi.customVideoMemory` (#16, caps reported VRAM so games don't overcommit shared RAM), `d3d11.submitBeforePresent` (#20), `d3d11.cpuCachedDynamicResources` (#21).
   - **Performance:** register-resident temp arrays, about 2.2× on an indexed-temp shader (#22); Metal residency sets (#23).
   - They also measured each perf change A/B and recorded the results.
9. Heavily patched MoltenVK and KosmicKrisp: geometry shaders, transform feedback and sparse residency on Metal. Not usable by Fable directly, because Fable's Vulkan path is DXVK → MoltenVK on the host, but it shows the KosmicKrisp direction.
10. A **Metal compiler cache-path probe** (`MetalCompilerCache.swift:5-44`). It detects an unwritable or immutable Metal module cache and redirects it via SPI, and never deletes the original cache while another process may be using it.

### Diagnostics and UX
11. A **"Still working…" / "not responding" overlay** driven by GPU-activity counters and a guest heartbeat, so long shader compiles don't look like hangs (`Stall.swift:5-22`).
12. **Frame-pacing statistics:** flush → screen latency, refreshes per frame, stutter thresholds at 25/50 ms (`PerfStats.swift`).
13. **Report bundle with logs from both host and guest**, visible on disk before sending (`Report.swift`, `ReportWindow.swift`).
14. **Self-test modes** for display, input, overlay, settings and provisioning (`*SelfTest.swift`).
15. **Disk lock (flock)** so two app copies can't run the same image at once (`DiskLock.swift`).
16. **Onboarding:** a single "Create New Disk" wizard covering branch, size, client and EULAs. It downloads and verifies Valve's image, and after that the user just signs in to Steam (`CreateDiskWindow.swift`, `DiskCreator.swift`).
17. Remote Play / Moonlight, clipboard, suspend (`krun_pause`), whole-display MetalFX upscaling, DualSense passthrough via uhid, and up to 4 pads.
18. Sparkle in-app updates plus notarization (see §1).

---

## 3. What Fable does that SteaMac doesn't

- **Runs everything Windows, not just Steam.** GOG, Heroic import, Inno/InstallShield installers, arbitrary EXEs, and native Mac games all live in one library.
- **No VM tax:** no fixed RAM or GPU reservation, no 4.5 GB OS image or large sparse disk, and no virtio-gpu round trip per Vulkan call. Graphics is a single translation hop (D3D → Metal).
- **D3DMetal / GPTK / CrossOver.** D3DMetal covers far more of D3D12 than vkd3d-proton on Venus, whose 12_0/11_0 ceiling means many UE5 titles won't start in SteaMac.
- **Multiple engines per bottle**, with an engine canary and benchmark, a runtime manifest, and `PrefixRuntimeGate`.
- Game Doctor, recipes, anti-cheat database, ProtonDB hints, cross-backend crash signatures, donor/`.fbottle` sharing, DualSense adaptive triggers on the Mac side, and Authenticode-verified redistributables.
- **Privacy:** no telemetry or crash upload by default. `FeedbackReport.swift` only pre-fills a GitHub issue.
- **Licence:** both projects are open source, but Fable's GPL-3.0 is copyleft.

---

## 4. What we can learn (ranked)

Effort is S (≤1 day), M (a few days) or L (a week or more). Risk means the chance of regressions or maintenance burden.

| # | Idea | Where in Fable | Effort | Risk |
|---|---|---|---|---|
| 1 | **Ship a patched DXMT build.** Build upstream `3Shain/dxmt` at a pinned commit with the functional patches from `host/dxmt/patches/` (skip the wmtr-only #2 unless it is needed, and the VR #25/#26), and publish it as a Fable release asset referenced from `versions.json`. Their ledger already did the triage across ~25 forks. The crash fixes (#6–#12) and Direct2D/World of Tanks fixes (#13–#15) are the payoff. | `Sources/Fable/Resources/versions.json` (`dxmt` entry), `Components/DXMTManager.swift`; new `scripts/build-dxmt.sh` + a CI job; `THIRD-PARTY-NOTICES.md` | L (cross build needs mingw plus the Metal toolchain; patch #1 adds `prebuilt_metal_dir`) | M: the base is post-v0.80 upstream main, so canary it (`EngineCanary`) before making it the default |
| 2 | **Expose the new DXMT knobs** once #1 lands: `dxgi.maxFrameLatency` (input latency), `dxgi.customVideoMemory` set automatically from Mac RAM (8/16 GB Macs swap), `d3d11.submitBeforePresent`. | `Components/DXMTConfig.swift` (only `dxgi.maxFrameRate` today), `Components/MemoryDiet.swift` / `HardwareProfile.swift` for the VRAM cap, `UI/GameSettingsView.swift` | S | L: the config keys are ignored by builds that don't know them |
| 3 | **Ownership model for anything Fable writes into Steam's or game config:** remember the value written, back off if the user changed it, revert when the reason goes away, apply once with a marker. Use it for Steam-bottle tweaks such as `-language`, and later per-game Steam launch options in `userdata/<id>/config/localconfig.vdf` → `apps/<appid>/LaunchOptions`. Windows Steam doesn't accept `VAR=… %command%`, so this is arguments only. | `Utilities/SteamKeyValues.swift` (add a span-preserving editor), new `Components/SteamConfigDefaults.swift`, `Components/GameRecipeCatalog.swift` | M | M: only write when Steam is not running (check the bottle's processes via `ProcessActivity`), write atomically, and keep the file mode |
| 4 | **Gate recipes on what the device can actually do** (their DD2 + `vulkaninfo` pattern). Example: only apply a D3DMetal or DXMT recipe if the chip family, macOS version or engine version supports it; record why it was skipped. | `Components/GameRecipeCatalog.swift`, `Components/HardwareProfile.swift`, `Components/GameDoctor.swift` | S–M | L |
| 5 | **"Still compiling shaders…" indicator.** If a launched game has had no window for N seconds but its process tree is burning CPU, show "Still working (compiling shaders)" instead of letting users force-quit; show "not responding" when CPU is idle too. | `ViewModels/ActivityMonitor.swift`, `Components/ProcessActivity.swift`, `ViewModels/GameLauncher.swift`, a toast or overlay in `UI/` | M | L |
| 6 | **Diagnostics bundle saved to disk.** "Save diagnostics…" zips the bottle's last launch log, `bottle.json`, engine and manifest info, and Doctor findings, with home paths redacted, into `~/Library/Logs/Fable/reports/<date>/`, and the GitHub issue tells users to attach it. Fable still uploads nothing itself. | `Components/FeedbackReport.swift`, `UI/FeedbackSheet.swift`, `Utilities/LogPruner.swift` | S | L |
| 7 | **Steam client defaults inside Steam bottles,** using #3's mechanism, applied once. SteaMac turns the idle screensaver off and background shader processing on (their reasons are in the scripts). For Windows Steam under Wine the more valuable candidates are **my suggestions, not things SteaMac does**: turning off GPU-accelerated web views and Steam's in-game overlay. Their exact storage keys must be checked against a real `config.vdf`/`localconfig.vdf` before writing anything. | new `Components/SteamConfigDefaults.swift`, called from the Steam bottle path in `GameLauncher.swift` | M | M: getting a key wrong silently does nothing, and a parse error must leave the file untouched |
| 8 | **Sparkle 2 with an EdDSA appcast** for in-app updates, keeping today's GitHub check as the fallback for translocated or read-only copies (their `UpdateCheck.swift` split). Their checker also sends an ETag and a 6 h throttle, which is cheap to copy now. | `ViewModels/AppUpdateChecker.swift`, `ViewModels/UpdateManager.swift`, `Package.swift` | ETag/throttle S; Sparkle M | M: works best alongside notarization, which is still the user's decision |
| 9 | **Metal cache-path robustness:** before snapshotting or restoring, probe that the Darwin Metal cache is writable and never remove a cache a running Wine might be using. | `Components/ShaderCache.swift`, `ViewModels/ShaderCacheStore.swift` | S | L |
| 10 | **Opt-in community compatibility stats** (chip, RAM, engine, backend, "reached a window?", average FPS, rating) feeding a public page and Fable's `GameConfidence`. A large differentiator, but it needs a backend and a privacy review; match SteaMac's "never sent" list (`GameStats.swift:18-19`) and keep it **off by default**, unlike their Sentry. | `ViewModels/GameStatsStore.swift`, `Components/GameConfidence.swift`, a new small service | L | M (privacy, ops) |
| 11 | **Self-test entry points** (`--selftest-*`) for the parts we can't unit-test, such as the launch-env assembly per backend and DXMT/DXVK DLL placement, run in CI. | `Tests/`, `ViewModels/GameLauncher.swift` | M | L |

### On the specific Steam-client questions
- **Black window / CEF / `steamwebhelper`:** SteaMac has nothing here. Fable's existing answers are better informed than anything in their repo:
  - `-cef-disable-gpu-compositing` (`BottleTemplateCatalog.swift:101-116`)
  - Sikarugir's D3DMetal env (`GameLauncher.swift:305-315`)
  - the `steamwebhelper.exe` AppDefaults override that keeps D3DMetal out of CEF on Wine 11 (`Sikarugir11Manager.swift:337-346`)

  SteaMac's structural lesson, "don't run Windows Steam if you can avoid it", supports Fable's native-Steam-bridge direction. For the Wine 11 black square specifically, the next experiments are untested here: extending the AppDefaults trick to other DLLs (e.g. `d3d11`/`dxgi` → builtin wined3d for `steamwebhelper.exe` only), and `-cef-force-32bit`/`-cef-single-process` style flags.
- **`-noverifyfiles`:** not used by SteaMac.
- **CEF flags:** none in SteaMac.
- **`steamwebhelper` patches:** none in SteaMac.
- **Not transferable:** hardware TSO (Rosetta already handles memory ordering for Wine), Venus/virgl patches, gamescope, and KosmicKrisp. KosmicKrisp is worth watching as a future MoltenVK replacement for Fable's DXVK path on macOS 26+.

---

## 5. Licence compatibility (Fable is GPL-3.0)

| SteaMac part | Licence | Into Fable (GPL-3.0)? | Conditions |
|---|---|---|---|
| Launcher Swift, guest scripts, build scripts | Apache-2.0 | **Yes, one-way** (Apache-2.0 is GPLv3-compatible) | Keep the copyright and `NOTICE` attribution, mark changed files, and include the Apache licence text in `THIRD-PARTY-NOTICES.md`. In practice we are borrowing ideas, not code, so a credit line is enough unless code is copied. |
| `host/dxmt/patches/` and DXMT itself | LGPL-2.1-or-later | **Yes** | If Fable *redistributes* a patched DXMT binary (idea #1), it must also publish the exact source: the pinned upstream tarball plus patches, as SteaMac does with `gpl-sources.tar`. Keep each patch's author. Don't submit these patches to 3Shain/dxmt: upstream refuses AI-assisted contributions, and several patches are AI co-authored. |
| Mesa / virglrenderer patches, Valve deckard-derived files | MIT | Yes | Keep the notices. |
| Kernel patches and config | GPL-2.0-only | Not compatible with GPLv3 for combination | Irrelevant: Fable has no use for them. |
| willfaust/dxmt (mentioned in their ledger) | GPL-3.0 | Compatible with Fable itself. Putting it into DXMT would make that DXMT build GPL-3.0. | SteaMac deliberately re-implemented two ideas from it instead of copying. |

**Action item, independent of SteaMac:** fix `THIRD-PARTY-NOTICES.md:37`. DXMT is LGPL-2.1-or-later upstream (`3Shain/dxmt/LICENSE`; the old zlib text is `LICENSE.OLD`).
