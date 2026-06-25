# Fable

**Play Windows games on your Mac — for free, including Steam.** Fable is a
native macOS app that manages Wine bottles with a choice of DirectX-to-Metal
translation layers. It's a free, open alternative to CrossOver (€76): it
renders Steam's login, installs games end-to-end, and plays modern DirectX 12
titles — no paid engine required.

> Tested on Apple Silicon (M-series), macOS 14+. Built with Command-Line-Tools
> Swift — no Xcode required.

## Highlights

- **Free Steam that actually works.** Steam's embedded Chromium (CEF) login
  renders — text, QR code, the works — through the free Sikarugir + D3DMetal
  path, with no CrossOver dependency. Games **download and install
  end-to-end**, and installs that stall on Apple's WoW64 service gap are
  **finished automatically** by Fable.
- **Plays modern games, including DirectX 12.** DEATHLOOP (30 GB D3D12 AAA),
  System Shock 2, Balatro and more run through Fable. Heavy titles auto-tune
  (60 fps cap + MetalFX) so they hold a steady frame rate.
- **Click and play.** A clean, game-first interface by default. Flip on
  **Advanced Mode** when you want the full cockpit.
- **Smart Bottle.** Fable scans a game, recommends the right backend, and
  applies a known-good setup in one click — backed by a growing, data-driven
  recipe catalog.

## Graphics backends

Pick per bottle (or per game); Smart Bottle suggests the right one.

| Backend | Path | Best for |
|---|---|---|
| **Built-in Wine** | wined3d (DirectX → OpenGL → Metal) | older DirectX 9–11 games |
| **DXMT** | DirectX 10/11 → Metal | modern D3D11 games |
| **DXVK + vkd3d** | DirectX 9–12 → Vulkan → MoltenVK → Metal | Vulkan-friendly / D3D9 (e.g. NewDark) |
| **Sikarugir** | Wine 10 + D3DMetal → Metal | **DirectX 12 and Steam's CEF — the free flagship** |
| **Apple GPTK** | Game Porting Toolkit + D3DMetal (Wine 7.7) | legacy fallback |
| **CrossOver** | your installed CrossOver engine | optional, requires the paid app |

## What it does

- **Bottles** — isolated Wine prefixes, each with its own Windows version,
  games, graphics backend, and settings. Create, rename, clone, repair,
  export/import (`.fbottle`), delete.
- **Games** — run Windows installers inside a bottle, import portable games
  (whole-folder or just the `.exe`), or unpack **GOG offline installers
  directly** via innoextract — no installer execution needed. Launch straight
  from the grid, or generate a double-clickable desktop shortcut.
- **Steam** — a one-click Steam bottle; CEF rendering via Sikarugir; download
  tuning (msync, which fixes the IOCP spin that throttles large downloads);
  and self-healing installs that finish the commit step Apple's WoW64 service
  can't.
- **Performance** — per-bottle frame-rate cap, MetalFX upscaling, and Apple's
  Metal HUD. Heavy D3DMetal titles get sensible defaults automatically.
- **Dependencies** — one-click runtimes: Visual C++ 2015–2022, OpenAL,
  DirectX (June 2010), plus 500+ winetricks verbs.
- **Components** — Wine and the translation layers are downloaded on first
  use, SHA-256-verified, and updatable from the Components tab.
- **Debugging (Advanced Mode)** — every launch writes a log
  (`~/Library/Application Support/Fable/Logs/`), reachable from each game's ⋯
  menu; `winecfg` and `regedit` are one click away per bottle.

## Requirements

- Apple Silicon Mac, macOS 14+
- **Rosetta 2** — Windows games are x86; install with
  `softwareupdate --install-rosetta`
- A few hundred MB for components, plus your games
- For the D3DMetal-backed paths (Sikarugir / GPTK), Apple's D3DMetal framework
  is sourced from a Game Porting Toolkit / Sikarugir install on your machine —
  it isn't redistributable, so Fable harvests it locally rather than bundling it.

## Installing

1. Download (or build) `Fable.app` and drag it to `/Applications`.
2. **Gatekeeper:** Fable is ad-hoc signed, not yet notarized. Clear the
   quarantine flag on a downloaded copy:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Fable.app
   ```
3. Launch Fable and create a bottle — Wine downloads automatically (verified)
   and the prefix initializes. The first bottle takes a couple of minutes;
   later ones (and Steam bottles, which clone a known-good install) are fast.

## Building from source

Requires Swift 6.2 (Command Line Tools are enough — no Xcode):

```sh
git clone https://github.com/malagic99/fable.git
cd fable
./scripts/make-app.sh   # release build → ./Fable.app
```

`swift run` works for development; `swift test` runs the suite (200+ tests;
swift-testing is pulled as a pinned SwiftPM dependency because CLT ships
neither XCTest nor swift-testing). `make-app.sh` embeds `innoextract` if
Homebrew's copy is present.

## How it works

Pinned component versions and checksums live in
`Sources/Fable/Resources/versions.json`. Everything Fable writes lives under
`~/Library/Application Support/Fable/` (`Bottles/`, `Components/`, `Logs/`,
`config.json`) — deleting that folder is a full reset.

The interesting bits: Steam's CEF renders by pointing D3DMetal at its framework
(`D3DMETAL_FRAMEWORK_PATH`); large downloads use `WINEMSYNC` instead of esync to
avoid a syscall-spin that pins the CPU and stalls transfers; and installs that
Apple's 32-bit WoW64 service can't commit are completed by Fable moving the
already-extracted files into place and writing the Steam manifest.

## Known limitations

- **Anti-cheat & some DRM** — kernel anti-cheat (EAC/BattlEye/Vanguard) and a
  few aggressive packers (certain Denuvo/repack titles) don't run under any
  macOS Wine. Smart Bottle flags these before you waste time.
- **Very large Steam downloads** (tens of GB, many depots) can be slow, since
  Steam's scheduler can starve the shared redistributables on the WoW64 stack.
- **D3DMetal sourcing** — the Sikarugir/GPTK backends need Apple's
  (non-redistributable) D3DMetal, acquired from a local GPTK/Sikarugir install.
- Ad-hoc signed: a downloaded copy needs the `xattr` step above until notarized.

## License & credits

Fable stands on Wine (LGPL), DXMT (zlib), DXVK/vkd3d-proton, MoltenVK, Apple's
Game Porting Toolkit (D3DMetal), Sikarugir, innoextract (zlib), and the Gcenx
packaging work. Respect the licenses of any games you run, and each store's
terms for their installers.
