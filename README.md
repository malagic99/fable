# Fable

**Run Windows games on your Mac.** Fable is a native macOS app that manages
Wine bottles with DirectX-to-Metal translation (DXMT) — a free, open
alternative to CrossOver, in the spirit of Whisky.

## What it does

- **Bottles** — isolated Wine prefixes, each with its own Windows version,
  games, registry, and settings. Create, rename, repair, delete.
- **Games** — run Windows installers inside a bottle, import portable
  games (copying just the .exe or its whole folder), or unpack **GOG
  offline installers directly** — no installer execution needed.
- **DXMT** — DirectX 11/10 → Metal translation per bottle, with a
  frame-rate cap and log-level control. Toggle anytime; the next launch
  picks it up.
- **Dependencies** — one-click installs of the runtimes games expect:
  Visual C++ 2015–2022 (64/32-bit), OpenAL, DirectX 9 (June 2010).
- **Components** — Wine and DXMT are downloaded on first use,
  SHA-256-verified, and updatable from the Components tab (update
  checksums come from GitHub's own asset digests).
- **Debugging** — every launch writes a log
  (`~/Library/Application Support/Fable/Logs/`), reachable from each
  game's ⋯ menu. `winecfg` and `regedit` are one click away per bottle.

## Requirements

- Apple Silicon Mac (tested on M4 Pro), macOS 14+
- **Rosetta 2** — Windows games are x86; Wine runs under Rosetta.
  Install with: `softwareupdate --install-rosetta`
- ~600 MB disk for components, plus your games

## Installing

1. Download (or build) `Fable.app` and drag it to `/Applications`.
2. **Gatekeeper:** Fable is ad-hoc signed, not notarized. macOS will
   refuse to open a downloaded copy until you clear the quarantine flag:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Fable.app
   ```

   (Right-click → Open works on some macOS versions but not all.
   This is also why a downloaded Wine tarball placed manually must be
   de-quarantined — macOS kills quarantined unsigned binaries.)
3. Launch Fable, create a bottle — Wine 11.0 downloads automatically
   (~190 MB, verified) and the prefix is initialized. First bottle takes
   a couple of minutes; later ones are much faster.

## Using it

**Install a game from GOG:** download the *offline backup installer*
from GOG.com → bottle page → **Run Installer…** → pick the setup exe →
choose **Extract Directly** (recommended; old GOG installers crash
Wine) → install the bundled dependencies when offered → pick the
game's .exe. Done — press ▶.

**Install from a generic installer:** **Run Installer…** → the
installer's own windows appear → finish it → **Add Installed Game…**.

**Portable / already-downloaded games:** **Add Game…** → pick the .exe
→ choose whole-folder copy (recommended) or just the exe.

**DXMT:** enable it in the bottle's Graphics section for D3D11/D3D10
games. Leave it off for D3D9-era titles (they use Wine's built-in
rendering) — and note D3D12-only games (e.g. UE5 titles like STALKER 2)
are not supported by DXMT.

**If a game won't start:** ⋯ menu → **Show Last Log**. Missing-DLL
errors usually mean a dependency — try the bottle's Dependencies
section first.

## Building from source

Requires Swift 6.2 (Command Line Tools are enough — no Xcode needed):

```sh
git clone <this repo>
cd FABLE
./scripts/make-app.sh   # release build → ./Fable.app
```

`swift run` works for development; `swift test` runs the suite
(swift-testing is pulled as a pinned SwiftPM dependency because CLT
ships neither XCTest nor swift-testing).

Optional integration tests against real artifacts:

```sh
FABLE_WINE_TARBALL=/path/to/wine-stable-11.0_1-osx64.tar.xz \
  swift test --filter WineIntegrationTests

FABLE_GOG_INSTALLER=/path/to/setup_somegame.exe \
  swift test --filter GOGExtractionIntegrationTests
```

`make-app.sh` embeds `innoextract` (with its dylibs, install-names
rewritten) if Homebrew's copy is present; without it the app falls back
to a Homebrew/MacPorts lookup at runtime.

## How it works

| Piece | Source | Role |
|---|---|---|
| Wine 11.0 (stable) | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds) | Runs Windows binaries (x86-64 under Rosetta; 32-bit via WoW64) |
| DXMT 0.80 | [3Shain/dxmt](https://github.com/3Shain/dxmt) | D3D11/10 → Metal (DLLs into system32, winemetal.so beside Wine) |
| innoextract | [constexpr.org/innoextract](https://constexpr.org/innoextract/) | Unpacks GOG offline installers without running them |

Pinned versions and checksums live in
`Sources/Fable/Resources/versions.json`. Everything the app writes
lives under `~/Library/Application Support/Fable/`
(`Bottles/`, `Components/`, `Logs/`, `config.json`) — deleting that
folder is a full reset.

## Known limitations

- **No D3D12** — needs Apple's Game Porting Toolkit (D3DMetal)
  integration; not included.
- **Old GOG installers crash if run under Wine** (WoW64 stack
  overflow, all current macOS Wine builds) — that's why Extract
  Directly exists. Use it.
- **Steam** works to varying degrees; its embedded browser is fragile
  under Wine. Blank login window = known upstream issue.
- Ad-hoc signed: every download needs the `xattr` dance above.

## License & credits

Fable stands on Wine (LGPL), DXMT (zlib/libpng), innoextract (zlib),
and the Gcenx packaging work. Respect the licenses of any games you
run, and GOG's terms for offline installers.
