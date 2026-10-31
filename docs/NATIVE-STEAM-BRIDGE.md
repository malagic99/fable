# Native Steam Bridge — plan

> **Status: Phase 0 spike passed — GO (2026-10-31).** A real Windows-only
> build (MOLEK-SYNTEZ, 64-bit .NET, D3D11) ran on a scratch copy of free
> Sikarugir, its own `steam_api64.dll` reached the native Mac Steam client
> through our `lsteamclient`, Mac Steam reported it `App Running`, and it
> rendered. No ntdll patch, no CrossOver, no changes to Steam. Results below
> under [Phase 0 result](#phase-0-result-2026-10-31). No Fable code yet.

## Phase 0 result (2026-10-31)

**(a) Bridge: PASS.**
- Valve's `proton_10.0` lsteamclient already handles macOS: under
  `__APPLE__` it loads `$STEAM_COMPAT_CLIENT_INSTALL_PATH/steamclient.dylib`.
- It needs only `ntdll_umbstowcs` / `ntdll_wcstoumbs` from `ntdll.so`, and
  Sikarugir exports both. The two functions NotProton's prebuilt needs aren't
  used upstream.
- Built against Wine 10.0. The Windows half builds through Wine's normal
  build; the 219-file C++ Unix half is built by hand with `clang++`, because
  upstream makedep has no C++ support.
- Configure under Rosetta with `CC="clang -arch x86_64"`; Apple's compiler
  shim targets arm64 even under `arch -x86_64`.
- Three source changes for macOS:
  - The Mac `steamclient.dylib` lacks `Steam_IsKnownInterface` and
    `Steam_NotifyMissingInterface`, so those are now optional.
  - Steam Input's key-code table is stubbed on macOS (a real Windows VK →
    `kVK_*` table is owed).
  - `lstrcpynA` / `lstrlenW` are defined for the Unix side.
- **The registry route works without an ntdll patch, given one naming rule.**
  A builtin copied into `Program Files` loads without its Unix half, because
  Wine only attaches it to builtins found in its own lib dirs by name. So the
  bridge also goes into the runtime as `steamclient64.dll`/`.so` (and
  `steamclient.dll`/`.so` for 32-bit).
- A tiny `steam.exe` stand-in writes `ActiveProcess\pid`, `SteamClientDll`,
  `SteamClientDll64`, `SteamPath` and `SteamExe`, then launches the game.
- Evidence:
  - A direct test program got `BLoggedOn: TRUE`.
  - MOLEK-SYNTEZ's own `steam_api64.dll` created the full `SteamAPI_Init`
    interface set, then called `GetAppID`, `GetSteamID` and
    `RequestCurrentStats`.
  - Mac Steam's `content_log` showed `AppID 1168880 state changed : Fully
    Installed,App Running,`.
  - The game rendered on D3DMetal.
- Getting the Windows files: Mac Steam's own console
  `download_depot <app> <depot>` fetched the Windows depot with no second
  login, which is easier than steamcmd.

**(b) Injection: PASS, with four requirements for the real hook.**
- Starting `steam_osx` directly with `DYLD_INSERT_LIBRARIES` loads the
  library. `open --env` is refused (launchd error 162).
- The variable reaches every Steam Helper (CEF) process too, so the hook must
  act only inside `steam_osx`.
- Steam's own post-update relaunch goes through LaunchServices and fails for a
  directly started client, so Fable has to let the bootstrapper apply updates
  or restart the client itself.
- Auto-login works, but took about 2 minutes in that run.
- Quit with `steam://exit`; AppleScript's quit didn't reach the injected
  instance.

**Not yet checked:** achievements unlocking, Cloud sync, playtime accrual, a
32-bit game, a SteamStub-DRM game. Steamworks SDK redistribution licence
stays open (Phase 4).

## The idea

Run a Windows game in a Fable bottle (Sikarugir, free) while it talks to the
**native macOS Steam client** you're already logged into — no Windows Steam
inside Wine at all. That retires the whole Steam-in-Wine saga in one move: the
CEF black square ([ARCHITECTURE.md](ARCHITECTURE.md)), the WoW64 install-commit
gap (`SteamInstallCommitter`), steamservice IPC, the overlay.

It's the principle behind [NotProton](https://github.com/NotProtonNot/NotProton)
(v1.2.3 read 2026-10-29), which does it with Valve's Proton pieces on a
**licensed CrossOver only**. Fable builds a **full equivalent** on the free
stack — including Windows games installing and launching from the Mac Steam
app itself — adapting the principle, not the code.

**Breakage is expected and accepted.** The Steam-side hook depends on Steam's
internals, and Valve ships client updates often. The design goal is not "never
breaks" but **breaks safely and is cheap to fix**: when a hook doesn't match,
Steam runs exactly as it does today and Fable says which Steam build needs
support.

## Two layers

**Layer 1 — the bridge** (needed either way). A game's Steam API calls reach
the Mac Steam client:

1. The game calls its own `steam_api64.dll` (`SteamAPI_Init`, ownership,
   achievements…).
2. That DLL loads the `steamclient64.dll` named by
   `HKCU\Software\Valve\Steam\ActiveProcess\SteamClientDll64`.
3. The key points at **our `lsteamclient.dll`** — a Wine builtin with a PE
   half and a Unix half.
4. The Unix half loads the Mac client's **`steamclient.dylib`** (x86_64 slice,
   since Wine runs under Rosetta) and forwards each call.
5. That library talks to the running Steam app over Steam's own IPC: login,
   ownership, achievements, "now playing", Cloud.

Plus a small **`steam.exe` stand-in** so games that check "is Steam running?"
find the registry keys and process they expect.

**Layer 2 — Steam integration** (what NotProton adds). A hook library loaded
into the Mac Steam client changes three decisions:

1. **Windows-only games are installable**, so Steam downloads their Windows
   depots itself.
2. **Steam Play is on**, with Fable offered as the compatibility tool.
3. **Play runs Fable's runner**: a small launcher that creates the game's
   bottle (`steamapps/compatdata/<appid>/pfx`) and starts it on Sikarugir with
   the bridge.

`steamcmd` stays as the fallback download path for when Layer 2 is broken.

## What we take, what we don't

| Piece | NotProton | Fable |
|---|---|---|
| **lsteamclient** — Wine builtin that forwards a game's Steam API calls to the Mac `steamclient.dylib` | macOS port, built for Wine 11.15 | **Build our own for Wine 10** from Valve's Proton source (Steamworks SDK licence, not GPL). NotProton's prebuilt can't load: Sikarugir's `ntdll.so` lacks `ntdll_get_dos_file_name` / `ntdll_get_unix_file_name` (6 of 8 imports present — checked). |
| **steam.exe shim** — sets the registry a game expects from a running Steam | port of Proton 9 `steam_helper` | Reuse the idea; BSD-3 if we borrow code |
| **ntdll detour** — redirects `steamclient64.dll` → `lsteamclient.dll` | binary patch at hardcoded RVAs, pinned per CrossOver build | Try **no patch** first (registry `SteamClientDll64`); patch Sikarugir's ntdll only if needed, pinned by hash |
| **Getting the hook into Steam** | `LSEnvironment.DYLD_INSERT_LIBRARIES` written into `/Applications/Steam.app`'s Info.plist, dylib dropped into the bundle, Steam.app ad-hoc re-signed | **Start the real client (`steam_osx`) with `DYLD_INSERT_LIBRARIES` in its environment.** No file in Steam modified, Valve's signature untouched — see the facts below. Untested: whether `steam_osx` runs properly started without its bootstrapper. |
| **Finding Steam's functions** | byte signatures per Steam client build, compiled in | Byte signatures in a **data file keyed by Steam build**, so a Steam update is fixed with a data entry, not a Fable release |
| **When Steam updates** | breaks until a new NotProton release | Hook **disables itself** on an unknown build or any signature miss; Steam runs normally; Fable names the build that needs support |
| Licence | GPLv3 (app + dylib) | Fable is MIT → **no NotProton GPL code enters Fable**. Reading it to understand the approach is fine; our code is written fresh from Valve's Proton source |

## Facts checked on this Mac (2026-10-31)

| Question | Answer | Why it matters |
|---|---|---|
| Can Rosetta Wine load the Mac `steamclient.dylib`? | **Yes** — `~/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steamclient.dylib` is universal: `x86_64 arm64` | Layer 1 is possible at all. Arm64-only would have killed it. |
| Is `/Applications/Steam.app` hardened? | **Yes** — `flags=0x10000(runtime)`, Team ID `MXGJJ98X76` | It's only the bootstrapper. A hardened process prunes `DYLD_*` vars, so injecting through it fails — why NotProton re-signs it. |
| Is the real client `steam_osx` hardened? | **No** — `flags=0x0(none)`, same Team ID, universal | `DYLD_INSERT_LIBRARIES` should be honoured when Fable starts `steam_osx` directly. **Spike must prove** Steam is happy started that way. |
| Which slice does the hook need? | arm64 (`steam_osx` runs native on Apple Silicon); build universal | The hook (in Steam) and the bridge (in Wine, x86_64) are separate processes |

## Risks we accept knowingly

- **Steam updates break Layer 2.** Mitigated by data-driven signatures,
  self-disable, and the `steamcmd` fallback — never by pinning users to an old
  Steam.
- **Account risk is unknown.** Changing how the Steam client behaves is a grey
  area under the Steam Subscriber Agreement. No account actions against
  NotProton users are known, but that isn't a guarantee. Layer 2 is opt-in and
  says so in plain words.
- **Anti-cheat games are out of scope.** The bridge doesn't change that.
- **The overlay won't work** through the bridge.

## Considered and rejected: Valve's precompiled shader caches

Steam's "Shader Pre-Caching" (Linux/SteamOS) ships per-game **Fossilize**
databases: Vulkan pipeline descriptions + SPIR-V from DXVK/vkd3d-proton, plus
binaries compiled for the Deck's AMD GPU. No use here:

- **Sikarugir/D3DMetal never touches Vulkan** — DirectX goes straight to
  Metal, so there's nothing for a Fossilize database to feed.
- **The compiled part is AMD machine code.**
- On the DXVK path (MoltenVK), a replay would need Fable's DXVK to emit the
  same SPIR-V as the recorder's, and whether a replayed MoltenVK pipeline
  persists into Metal's cache is unproven.
- Steam serves these only to Linux clients with Steam Play; getting them for
  Mac Steam would mean posing as Linux. Not doing that.

**One exception worth a later look:** the same depot carries **pre-converted
videos** (`fozmediav1/`) that Proton swaps in when Wine's Media Foundation
can't play a cutscene. They're plain video files, GPU-independent, and Fable's
games hit the same Media Foundation gaps. Only reachable once Layer 2 lets Mac
Steam download a game's Steam Play content; per broken game only.

Shared D3DMetal caches stay impossible (keyed to exact GPU + driver build, no
replay mechanism). Fable already keeps your own cache across reboots.

## Timeline

Personal-project pace: evenings and weekends, with real-game testing
interrupting as always. Dates are targets, gates are real.

| Phase | Target | Gate to pass |
|---|---|---|
| **0 — Spike** | Nov 2 – Nov 8 | (a) One owned Windows-only Steam game reaches `SteamAPI_Init` = true against native Steam, in a Sikarugir copy. (b) `steam_osx` started directly with a do-nothing injected dylib logs in and runs normally. |
| **1 — Bridge in Fable** | Nov 9 – Nov 22 | Download (steamcmd) → launch → quit for that game entirely from Fable's UI |
| **2 — Steam integration** | Nov 23 – Dec 13 | That game installs and launches from the Mac Steam app's Play button, with Fable as the compatibility tool; an unknown Steam build disables the hook cleanly |
| **3 — Hardening** | Dec 14 – Dec 27 | 5 games across DRM / 32-bit / D3D11 / D3D12 work; a Steam client update is survived by a data-file entry alone; failures have Doctor signatures |
| **4 — Ship** | Dec 28 – Jan 3 | Licence cleared, bridge + hook built in CI, second-Mac test passes → v1.1.0 |

**Kill criteria** (any one stops the project and parks it here with the
evidence): native Steam refuses a Windows app's API session; Wine 10 can't host
the bridge without rebuilding Sikarugir itself; the Steamworks licence forbids
redistributing the built bridge and there's no install-time-build alternative.
**Layer 2 alone** is dropped (bridge + steamcmd still ship) if `steam_osx`
won't run with an injected dylib and the only way in is re-signing Valve's
app.

## Task list

### Phase 0 — Spike (go / no-go)

- [x] Pick the test game: owned, Windows-only, calls the Steam API, small, no anti-cheat
- [x] **Ask first**, then install the toolchain: `mingw-w64` (or llvm-mingw), `bison`, `flex`
- [x] Clone Wine `wine-10.0`; configure an x86_64 + i386 tree for the Rosetta host (pattern: NotProton `bridge/setup-wine-tree.sh`)
- [x] Fetch Proton's lsteamclient (`proton_10.0` branch) + Steamworks headers
- [x] Port to macOS: `steamclient.dylib` path, Mach-O loading — use Valve's code; NotProton's lsteamclient diff only as a reference (Steamworks-licensed, not its GPL parts)
- [x] Build `lsteamclient.dll` (x86_64, i386) + `lsteamclient.so`; confirm every `ntdll.so` import exists in Sikarugir's
- [x] Copy Sikarugir to scratch (never touch the installed one); drop the bridge in `lib/wine/*`
- [x] Download the game's Windows depot (done via Mac Steam's console `download_depot`; steamcmd stays the scripted path): `steamcmd +@sSteamCmdForcePlatformType windows +login <you> +app_update <id>` — **you type your own credentials**
- [x] Load route A: point `HKCU\Software\Valve\Steam\ActiveProcess\SteamClientDll64` at the bridge; launch with `SteamAppId`/`SteamGameId` set and Mac Steam running
- [x] ~~If A fails: route B~~ not needed — A works with the naming rule above. Route B — port the detour idea to Sikarugir's ntdll, pinned by its SHA-256
- [x] Record: init result, ownership check, achievements, Steam's "now playing", playtime, overlay (expect none), Cloud
- [x] **Injection check:** quit Steam; start `steam_osx` directly with `DYLD_INSERT_LIBRARIES` pointing at a do-nothing universal dylib that only logs it loaded. Does Steam log in, update and run normally? Does it relaunch through the bootstrapper and drop the variable?
- [x] Write the go / no-go here, with log lines

### Phase 1 — Bridge in Fable

- [ ] `SteamBridge` component: install/verify the bridge into Sikarugir's runtime, hashes pinned (pattern: `SikarugirManager`)
- [ ] `SteamCmdManager`: fetch Valve's steamcmd, run `app_update` forced to Windows with progress, login handed to Terminal (Fable never sees credentials)
- [ ] Library source "Steam (native bridge)": imports bridge-installed games; never labelled Mac-native (fixes the importer gap noted in memory `notproton-teardown`)
- [ ] Launch path: one more branch in `composeLaunchPlan` (bridge env + `SteamAppId`) behind the existing `RuntimeResolving` seam, with `LaunchPlanTests`
- [ ] Preflight: native Steam running and logged in → otherwise a clear nudge, not a silent failure
- [ ] Per-game prefix creation reusing `WineManager.createPrefix`; `PrefixRuntimeGate` respected
- [ ] es/pt strings for every new view literal (the gate fails otherwise)

### Phase 2 — Steam integration

- [ ] Hook dylib (universal), written fresh: reads the signature data file, finds the three decision points (installable platform, Steam Play availability, launch command), and **does nothing** unless every signature for the running Steam build matches
- [ ] Signature data file: keyed by Steam client build, each entry a byte pattern + expected match count; shipped with Fable, updatable without code changes
- [ ] `SteamLauncher`: Fable starts `steam_osx` with the hook (opt-in toggle, plain-words warning about the account grey area); "Restore normal Steam" stops it and relaunches Steam the ordinary way
- [ ] Compatibility tool: register Fable's runner; it maps `<appid>` → `compatdata/<appid>/pfx` bottle on Sikarugir + bridge and launches the exe Steam hands it
- [ ] Status in Fable: "Steam integration active / disabled for Steam build N / not started", never silent
- [ ] Doctor rule: hook disabled because of an unknown Steam build → names the build

### Phase 3 — Hardening

- [ ] Test matrix: a SteamStub-DRM title, a 32-bit title, a D3D11 and a D3D12 title, one existing recipe game (DEATHLOOP or Ready or Not) — compare against the Steam-in-Wine path
- [ ] Steam Cloud: does sync happen for a bridge-launched game? If not, say so in the UI
- [ ] Survive one real Steam client update: add its data entry, no code change
- [ ] Updates via Steam (Layer 2) or `steamcmd app_update` (fallback); uninstall removes depot + prefix
- [ ] Doctor signatures for bridge failures, each pinned to a real log line
- [ ] Recipes gain a "bridge OK" field only from tested runs
- [ ] Later, per broken cutscene: try Steam's pre-converted videos (`fozmediav1/`)

### Phase 4 — Ship

- [ ] Read the Steamworks SDK licence for redistributing a built `lsteamclient`; if blocked, build at install time instead
- [ ] CI job that builds the bridge and hook reproducibly (pinned Wine commit, like NotProton's `WINE_COMMIT`)
- [ ] `docs/wine-quirks.md` + `ARCHITECTURE.md` sections; FRIEND-README note
- [ ] Second-Mac test (the only honest test — Rock 2's lesson)
- [ ] CHANGELOG → `scripts/release.sh` → v1.1.0
