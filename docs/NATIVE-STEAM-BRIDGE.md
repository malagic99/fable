# Native Steam Bridge — plan

> **Status: proposed, 2026-10-29. Nothing built yet.** Phase 0 is a spike whose
> only job is to say go or no-go before any Fable code is written.

## The idea

Run a Windows game in a Fable bottle (Sikarugir, free) while it talks to the
**native macOS Steam client** you're already logged into — no Windows Steam
inside Wine at all. That retires the whole Steam-in-Wine saga in one move: the
CEF black square ([ARCHITECTURE.md](ARCHITECTURE.md)), the WoW64 install-commit
gap (`SteamInstallCommitter`), steamservice IPC, the overlay.

It's the principle behind [NotProton](https://github.com/NotProtonNot/NotProton)
(v1.2.3 read 2026-10-29), which does it with Valve's Proton pieces on a
**licensed CrossOver only**. Fable adapts the principle, not the code.

## What we take, what we don't

| Piece | NotProton | Fable |
|---|---|---|
| **lsteamclient** — Wine builtin that forwards a game's Steam API calls to the Mac `steamclient.dylib` | macOS port, built for Wine 11.15 | **Build our own for Wine 10** from Valve's Proton source (Steamworks SDK licence, not GPL). NotProton's prebuilt can't load: Sikarugir's `ntdll.so` lacks `ntdll_get_dos_file_name` / `ntdll_get_unix_file_name` (6 of 8 imports present — checked). |
| **steam.exe shim** — sets the registry a game expects from a running Steam | port of Proton 9 `steam_helper` | Reuse the idea; BSD-3 if we borrow code |
| **ntdll detour** — redirects `steamclient64.dll` → `lsteamclient.dll` | binary patch at hardcoded RVAs, pinned per CrossOver build | Try **no patch** first (registry `SteamClientDll64`); patch Sikarugir's ntdll only if needed, pinned by hash |
| **Steam.app hooks** — inject dylib, force Steam Play, re-sign Steam.app | yes, byte signatures per Steam build | **No.** Fragile and invasive. Download Windows depots with Valve's `steamcmd` instead |
| Licence | GPLv3 (app + dylib) | Fable is MIT → **no NotProton GPL code enters Fable** |

## Timeline

Personal-project pace: evenings and weekends, with real-game testing
interrupting as always. Dates are targets, gates are real.

| Phase | Target | Gate to pass |
|---|---|---|
| **0 — Spike** | Nov 2 – Nov 8 | One owned Windows-only Steam game reaches `SteamAPI_Init` = true against native Steam, in a Sikarugir copy |
| **1 — Prototype in Fable** | Nov 9 – Nov 22 | Download → launch → quit for that game entirely from Fable's UI |
| **2 — Hardening** | Nov 23 – Dec 6 | 5 games across DRM / 32-bit / D3D11 / D3D12 work; failures have Doctor signatures |
| **3 — Ship** | Dec 7 – Dec 13 | Licence cleared, bridge built in CI, second-Mac test passes → v1.1.0 |

**Kill criteria** (any one stops the project and parks it here with the
evidence): native Steam refuses a Windows app's API session; Wine 10 can't host
the bridge without rebuilding Sikarugir itself; the Steamworks licence forbids
redistributing the built bridge and there's no install-time-build alternative.

## Task list

### Phase 0 — Spike (go / no-go)

- [ ] Pick the test game: owned, Windows-only, calls the Steam API, small, no anti-cheat
- [ ] **Ask first**, then install the toolchain: `mingw-w64` (or llvm-mingw), `bison`, `flex`
- [ ] Clone Wine `wine-10.0`; configure an x86_64 + i386 tree for the Rosetta host (pattern: NotProton `bridge/setup-wine-tree.sh`)
- [ ] Fetch Proton's lsteamclient (`proton_10.0` branch) + Steamworks headers
- [ ] Port to macOS: `steamclient.dylib` path, Mach-O loading — use Valve's code; NotProton's lsteamclient diff only as a reference (Steamworks-licensed, not its GPL parts)
- [ ] Build `lsteamclient.dll` (x86_64, i386) + `lsteamclient.so`; confirm every `ntdll.so` import exists in Sikarugir's
- [ ] Copy Sikarugir to scratch (never touch the installed one); drop the bridge in `lib/wine/*`
- [ ] Download the game's Windows depot: `steamcmd +@sSteamCmdForcePlatformType windows +login <you> +app_update <id>` — **you type your own credentials**
- [ ] Load route A: point `HKCU\Software\Valve\Steam\ActiveProcess\SteamClientDll64` at the bridge; launch with `SteamAppId`/`SteamGameId` set and Mac Steam running
- [ ] If A fails: route B — port the detour idea to Sikarugir's ntdll, pinned by its SHA-256
- [ ] Record: init result, ownership check, achievements, Steam's "now playing", playtime, overlay (expect none), Cloud
- [ ] Write the go / no-go here, with log lines

### Phase 1 — Prototype in Fable

- [ ] `SteamBridge` component: install/verify the bridge into Sikarugir's runtime, hashes pinned (pattern: `SikarugirManager`)
- [ ] `SteamCmdManager`: fetch Valve's steamcmd, run `app_update` forced to Windows with progress, login handed to Terminal (Fable never sees credentials)
- [ ] Library source "Steam (native bridge)": imports steamcmd-installed games; never labelled Mac-native (fixes the importer gap noted in memory `notproton-teardown`)
- [ ] Launch path: one more branch in `composeLaunchPlan` (bridge env + `SteamAppId`) behind the existing `RuntimeResolving` seam, with `LaunchPlanTests`
- [ ] Preflight: native Steam running and logged in → otherwise a clear nudge, not a silent failure
- [ ] Per-game prefix creation reusing `WineManager.createPrefix`; `PrefixRuntimeGate` respected
- [ ] es/pt strings for every new view literal (the gate fails otherwise)

### Phase 2 — Hardening

- [ ] Test matrix: a SteamStub-DRM title, a 32-bit title, a D3D11 and a D3D12 title, one existing recipe game (DEATHLOOP or Ready or Not) — compare against the Steam-in-Wine path
- [ ] Steam Cloud: does sync happen for a Fable-launched game? If not, say so in the UI
- [ ] Updates via `steamcmd app_update`; uninstall removes depot + prefix
- [ ] Doctor signatures for bridge failures, each pinned to a real log line
- [ ] Recipes gain a "bridge OK" field only from tested runs

### Phase 3 — Ship

- [ ] Read the Steamworks SDK licence for redistributing a built `lsteamclient`; if blocked, build at install time instead
- [ ] CI job that builds the bridge reproducibly (pinned Wine commit, like NotProton's `WINE_COMMIT`)
- [ ] `docs/wine-quirks.md` + `ARCHITECTURE.md` sections; FRIEND-README note
- [ ] Second-Mac test (the only honest test — Rock 2's lesson)
- [ ] CHANGELOG → `scripts/release.sh` → v1.1.0
