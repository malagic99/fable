# Third-party notices

Fable's own source is licensed under GPL-3.0-only (see [LICENSE](LICENSE));
releases up to v1.1.0 were published under MIT. It stands on other
people's work in two different ways, with different obligations:

## Redistributed inside Fable.app

`scripts/make-app.sh` embeds these binaries so GOG installers extract without
a Homebrew dependency:

| Component | License | Notes |
|---|---|---|
| **innoextract** | zlib | © Daniel Scharrer — <https://constexpr.org/innoextract/> |
| **Boost** (atomic, container, date_time, filesystem, iostreams, program_options, random, regex) | Boost Software License 1.0 | innoextract dependency |
| **ICU** (icudata, icui18n, icuuc) | Unicode/ICU License | innoextract dependency |
| **liblzma** | 0BSD | innoextract dependency |
| **libzstd** | BSD-3-Clause | innoextract dependency |
| **cabextract** | GPL-3.0-or-later | © Stuart Caie — <https://www.cabextract.org.uk/>; includes libmspack (LGPL-2.1). Run by winetricks to unpack fonts and runtimes; source at the link |
| **AreWeAntiCheatYet** data (`areweanticheatyet.json`) | MIT | © 2021 Starz0r, Curve — <https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet>, snapshot of `games.json` at commit 6c26305 trimmed to name, status and anti-cheat; licence text bundled as `areweanticheatyet-LICENSE.txt` |

zlib license (innoextract): *This software is provided 'as-is', without any
express or implied warranty. In no event will the authors be held liable for
any damages arising from the use of this software.* Full text ships with the
innoextract source.

Boost Software License 1.0: permits use and binary redistribution; the
license text must accompany source copies — it lives with the Boost sources.

## Downloaded at runtime, never redistributed by Fable

Fable downloads these from their origins on first use (SHA-256-verified) or
discovers them already installed on your machine. Their licenses govern your
copy directly:

- **Wine** (LGPL-2.1) — Gcenx macOS builds
- **DXMT** (zlib) — 3Shain
- **DXVK / vkd3d** (zlib / LGPL), **MoltenVK** (Apache-2.0)
- **winetricks** (LGPL-2.1)
- **Sikarugir** (GPL) — its Wine engines and wrapper template, downloaded
  from Sikarugir's own GitHub releases (the same files the Sikarugir app
  fetches); Fable assembles the engine and renderer locally
- **D3DMetal** (Apple, proprietary) — Fable never bundles or hosts it. It
  arrives inside Sikarugir's template, downloaded from Sikarugir's releases,
  or from a Game Porting Toolkit install already on your machine
- **CrossOver** (commercial) — optional backend that drives your own
  licensed installation

## Content

Game cover art is fetched from Steam's public CDN or SteamGridDB (with your
API key) for personal display and cached locally; Fable never redistributes
artwork. Games, installers, and the Steam client belong to their publishers
and Valve — Fable's donor export deliberately strips installed games and
account data so shared bottles carry none of either.
