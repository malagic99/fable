# FEX migration — how Fable survives the end of Rosetta

Every Wine backend Fable ships today is an **x86_64 macOS binary running under
Rosetta 2**. That's the load-bearing assumption under the whole app. This file
is the plan for the day that stops being true.

> **Status: watch-and-prepare, written 2026-08-04 (v0.23.1).**
> Only **Phase 0** is scheduled work. Phases 1–3 are gated on an artifact
> existing — do not start them on the strength of an announcement.

## Why this file exists

Two independent pressures point the same way:

1. **Rosetta's announced wind-down.** As announced at WWDC 2025, Rosetta 2 is
   supported through macOS 26 and 27, after which only a subset remains — aimed
   at older unmaintained *games*. That carve-out happens to point straight at
   Fable's use case, which is lucky. But a stack whose foundation is a
   compatibility carve-out is a stack with a clock on it. We're on macOS 27
   now: the last release with the full guarantee.
2. **Rosetta has no 32-bit x86 translator, and never will.** That single fact
   is the root cause of roadmap item **#82** being parked, of the
   `wine32on64` dependency, and of the PE32 installer breakage in
   [`PEInfo.swift`](../Sources/Fable/Utilities/PEInfo.swift). We've been
   waiting on Apple to ship modern-Wine-with-32-on-64. Apple has no reason to.

**FEX** ([FEX-Emu](https://github.com/FEX-Emu/FEX)) is the open-source
x86/x86-64 → ARM64 translator behind x86 gaming on Asahi Linux. Unlike Rosetta
it translates **32-bit x86 too**, and it plugs into Wine's WoW64/ARM64EC
emulator interface as `libwow64fex.dll` / `libarm64ecfex.dll`. It is the
technology that answers both pressures at once.

### Why this stopped being a fringe bet (2026-08-04)

Valve published Steam pages for **FEX** and **Lepton**, the compatibility
layers for the Arm-based **Steam Frame** headset (Snapdragon 8 Gen 3, SteamOS
on Arch). The shipping stack there is three layers: Proton for Windows
software, FEX for x86→Arm64 translation, Lepton (Waydroid) for Android.

That matters to us for one reason, and it isn't the headset: **FEX now has
Valve behind it**, aimed at the Steam library, on hardware Valve sells. It is
on track to become for CPU translation what Proton became for Windows-on-Linux
— funded, hardened against thousands of real games, and fixed in the open.
A technology bet on FEX is now a bet on a maintained platform layer rather
than on a volunteer emulator.

It also **widens where a FEX-era Wine could come from**. The original thesis
here was the CrossOver → Sikarugir rebuild pipeline. Valve's work is
Proton/upstream-Wine-shaped, and Wine's ARM64EC support is upstream, so the
free path may well arrive from the Proton lineage instead. Two independent
sources is a materially better position than one.

**What it does *not* change:** Steam Frame is Arm **Linux**. FEX still has no
macOS host port, and Valve has no reason to write one. The macOS-specific
blocker below is untouched — this news improves the odds that the *ingredients*
are excellent, not that someone has cooked them for macOS.

## The reframe: what Fable's job actually is

**Fable does not build Wine.** It downloads, detects, and manages backends. So
the plan here is *not* "port FEX to macOS" — that's a funded-team project.
The plan is:

> **Strip out the assumption that Wine is x86_64-under-Rosetta, so Fable can
> adopt an ARM64-native backend the week one becomes downloadable.**

The free path is a road we've already walked. Wine is LGPL, so a FEX-era
CrossOver's Wine tree gets published; FEX itself is MIT. The same community
pipeline that rebuilt CrossOver's tree into **Sikarugir** can produce a
FEX-era Sikarugir. Fable's job is to be the manager that's ready to consume it.

## What the stack looks like on each side

| | Today (Rosetta) | FEX era |
|---|---|---|
| Wine Unix side | `x86_64-unix` `.so`, translated | `aarch64-unix` `.so`, **native** |
| Wine PE side | `x86_64-windows` | `x86_64-windows` (emulated by FEX) |
| 32-bit guest | `wine32on64` / buggy WoW64 | `libwow64fex.dll` — a real answer |
| wineserver / IPC / FS | translated | **native** — meaningful perf win |
| Graphics translation | D3DMetal (Apple, closed, x86_64) | **must be arm64** — see blocker |
| CPU features | `ROSETTA_ADVERTISE_AVX=1` | FEX tunables; the Rosetta var is a no-op |

The under-appreciated win isn't the CPU translation — it's that Wine's Unix
half goes **native**. Much of Wine's overhead is syscall- and IPC-heavy
(wineserver round-trips, filesystem, sync primitives), and all of that is
translated today.

## The one blocker nobody can route around

**D3DMetal is Apple's closed x86_64 binary.** A native-ARM64 Wine cannot load
an x86_64 Unix-side `.so`, and Apple has no stated reason to ship an arm64
D3DMetal for a Wine they don't support. So in a FEX world, **our flagship
backend is the one that breaks.**

The escape hatch is already in the repo: **DXMT and DXVK + MoltenVK are open
source and build native arm64** (MoltenVK is arm64-native today). The FEX
transition therefore **inverts the backend hierarchy** — DXVK/DXMT become
first-class, D3DMetal becomes the legacy path. That exactly reverses the
current [ARCHITECTURE.md](ARCHITECTURE.md) ordering.

**Practical consequence for how we spend time now:** every hour on DXMT/DXVK
quality is FEX insurance. Every hour on D3DMetal-specific plumbing is not.
Weight the recipe and tuning work accordingly — this is the cheapest hedge
available, and it costs nothing if FEX never lands.

---

## Phase 0 — de-Rosetta the codebase ✅ **done 2026-08-04**

Cheap, pure cleanup, no user-visible behavior change. Worth doing even if FEX
never ships, because it's mostly removing hardcoded literals.

| # | Change | Where |
|---|---|---|
| 0.1 | Renderer overlay takes its two dispatch dirs from `WineLayout` instead of literals | [`SikarugirManager.swift`](../Sources/Fable/Components/SikarugirManager.swift) |
| 0.2 | Payload lookup + `lib/wine/<unix>` path derive from the layout, detected off the real Wine binary | [`DXMTManager.swift`](../Sources/Fable/Components/DXMTManager.swift) |
| 0.3 | `ROSETTA_ADVERTISE_AVX` is set only when `layout.isTranslatedHost` | [`WineEnv.swift`](../Sources/Fable/Components/WineEnv.swift) |
| 0.4 | `MachOInfo` — host-binary architecture reader (see correction below) | [`MachOInfo.swift`](../Sources/Fable/Utilities/MachOInfo.swift) |
| 0.5 | Bug reports carry the layout line, so a log says which world it came from | [`FeedbackReport.swift`](../Sources/Fable/Components/FeedbackReport.swift), `FeedbackSheet` |
| 0.6 | About copy no longer asserts "Wine runs under Rosetta 2" (+ es/pt) | [`SettingsView.swift`](../Sources/Fable/UI/SettingsView.swift) |

Two types carry it, both mirroring patterns already in the repo:

- **[`WineLayout`](../Sources/Fable/Components/WineLayout.swift)** — the one
  place that knows Wine's dispatch-directory names and whether the host side is
  translated. `.rosetta` and `.nativeARM64` presets; `detect(wineBinary:)`
  reads it off a real binary and falls back to `.rosetta` when unsure, because
  guessing "native" for an unparseable binary would break a working install.
  This is the `WineEnv` / `SteamPaths` centralization rule applied to
  architecture.
- **[`MachOInfo`](../Sources/Fable/Utilities/MachOInfo.swift)** — the host-side
  counterpart to `PEInfo`. `PEInfo` reads *guest* Windows binaries; this reads
  *host* Mach-O ones. Handles thin x86_64/arm64 and fat binaries (a fat binary
  with an arm64 slice runs native — the loader prefers it).

> **Correction to the original 0.4.** The plan said to probe
> `sysctl.proc_translated`. That's wrong: Fable is itself a native arm64 app,
> so asking about *our own* process always answers "not translated" no matter
> what the backend is — the field would have been permanently `false`. The
> honest source is the Wine binary's own Mach-O header, which is why 0.4 became
> `MachOInfo` instead of a `HardwareProfile` field.

**Verified live 2026-08-04:** both installed backends (Sikarugir 10.0,
GPTK 4.0-heroic) report `cputype 0x01000007` (x86_64) → `.rosetta`, so every
call site keeps today's behavior including the AVX flag. Covered by
`WineLayoutTests` (10 tests), and a `defaultsPreserveTodaysBehavior` test pins
the no-behavior-change guarantee. 435 tests green.

## Phase 1 — teach the backend model about architecture (gated)

`GraphicsBackend` in [`Bottle.swift:87`](../Sources/Fable/Models/Bottle.swift)
is a bare enum whose rawValues are persisted in every `bottle.json` — never
rename a case.

**Do not add a `.fex` case.** FEX is not a graphics backend; it's the CPU layer
underneath one. Instead add a sibling descriptor stored on the bottle:

- `guestArch` — `x86_64` / `i386`
- `emulator` — `rosetta` / `fex`

This is what lets a FEX bottle and a Rosetta bottle coexist in one library,
which we will need for the whole transition period. Schema migration: absent
fields default to `(x86_64, rosetta)`, so every existing bottle reads correctly.

## Phase 2 — the 32-bit unlock (the actual prize)

[`PEInfo.swift:8`](../Sources/Fable/Utilities/PEInfo.swift) already detects
`pe32`, and its comment already says PE32 "crashes Wine's WoW64 in several
installer unpackers." Today the only answer is the CrossOver-lineage
compatibility runtime.

With `libwow64fex.dll` in play, **PE32 detection stops being a warning and
becomes a routing decision** — send this binary to the FEX-WoW64 bottle. That:

- retires the compat-runtime workaround,
- fixes the GOG/InnoSetup installer class of bugs at the root,
- **unparks #82** without Apple shipping anything.

## Phase 3 — Doctor + recipes catch up

- New `GameDoctor` rules for FEX-specific signatures (JIT/AOT-cache failures,
  unsupported-instruction traps) — same data-driven pattern as the existing
  ~24 rules.
- FEX AOT cache management as a Fable-shaped feature: "warm the cache" before
  first play, the same way we handle shader caches.
- The recipe catalog gains an emulator axis; existing `Tested:` claims stay
  pinned to the backend *and emulator* they were verified on. Never migrate a
  tested claim across emulators without re-testing.

## Triggers — what starts Phase 1

Concrete and watchable. Not an announcement, an artifact:

- [ ] A CrossOver release whose Wine tree ships `aarch64-unix` dispatch dirs.
- [ ] FEX publishing macOS host support (it is Linux-host today). **The single
      highest-value thing to watch** — everything else follows from it.
- [ ] A Sikarugir-class free rebuild of a FEX-era tree, from either the
      CrossOver or the Proton/upstream lineage.
- [ ] An arm64-native D3D translation layer that works under it (most likely
      DXMT or DXVK+MoltenVK, per the blocker above).

## Honest uncertainties

- The CrossOver-pivot reporting that prompted this file, and the Valve /
  Steam Frame reporting above, are **not independently verified here** — both
  postdate the knowledge available to the author of this doc, and the Valve
  article in question visibly confuses "Steam Deck" with "Steam Frame" in
  several places, so treat its details as approximate. The technical plan
  holds regardless; see the artifact triggers before spending Phase 1 hours.
- FEX is generally **slower than Rosetta** on identical Apple hardware —
  Apple built silicon features specifically for Rosetta. Some of that gap
  closes because Wine's Unix half goes native, and some doesn't. Expect the
  first FEX-era backend to be a compatibility win and a perf regression.
- Whether Apple's post-27 "subset for older games" carve-out covers a Wine
  process at all is unknown. That's the whole reason this file exists.
