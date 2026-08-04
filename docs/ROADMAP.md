# Fable — Roadmap (month of 2026-07)

> **Status: living document, last updated 2026-07-10 (v0.22.3).**
> A themed one-month plan, not a burndown. Real-game debugging *will*
> interrupt it — that's fine, it has found every important bug so far.
> Supersedes the post-Friend-Kit menu (history in git).

## The governing goal (unchanged)

Fable is a **polished personal tool I share with friends — not a published
product.** No launch, no growth target. **"Done" = boringly reliable in real
use.** **1.0 = a friend is playing on it.** Everything below serves that or is
honestly parked.

## Where we are (v0.22.3, 408 tests, CI green on every PR)

- **Six backends**, flagship Sikarugir (modern Wine + matched D3DMetal): free
  Steam CEF renders, installs self-heal, AAA D3D12 plays. Why:
  [ARCHITECTURE.md](ARCHITECTURE.md). Fix map: [wine-quirks.md](wine-quirks.md).
- **One library** (Wine + native Mac), themes, DualSense raw-HID triggers,
  playtime/notes/health, hardware-aware perf, en/es/pt with a build-breaking
  coverage gate.
- **Fable Doctor**: ~24 log signatures incl. the cross-backend "it's the game,
  stream it" verdict, named missing DLLs, and the .NET-Framework / WPF /
  wineserver-collision rules from real debugging.
- **Sharing**: `.fablerecipe`, `.fableskin`, `.fbottle` (donor export strips
  games + login, streams with progress + disk preflight), `friend-kit.sh`,
  Send Feedback + Share This Setup (zero-backend GitHub pipes).
- **.NET**: Core (6/7/8) apps run (VotV/YeetPatch verified); the destructive
  `dotnet4x` footgun is guarded; real .NET Framework 4.8 installs on the GPTK
  backend (32-on-64) — see [DOTNET-FRAMEWORK-LAUNCHERS.md](DOTNET-FRAMEWORK-LAUNCHERS.md).

---

## 🪨 Rock 1 (leads the month) — Memory Diet

The STALKER 2 / TLOU2 unified-memory bleed: AAA ports budget against separate
RAM+VRAM pools, but on a 24 GB Mac that's one pool D3DMetal double-counts, so
streaming caches grow toward a budget that doesn't physically exist → wired-
memory crash. Two Fable-shaped pieces:

1. **Engine.ini streaming-pool cap writer.** Detect UE4/UE5 via the existing
   `CompatibilityScanner`, size the cap from `HardwareProfile` (already knows
   24 GB), write `[SystemSettings] r.Streaming.PoolSize=…` into the game's
   config as a **reversible per-game toggle**. A config-file ritual becomes a
   checkbox. Pure writer + tests; UI in the bottle's Performance section.
2. **Memory-pressure nudge.** The `ThermalMonitor` pattern for memory — a
   toast *before* the OOM crash, not the Doctor's `E_OUTOFMEMORY` verdict
   after. Only while a game runs (rubber-mat policy).
3. Verify on STALKER 2 + TLOU2 → **mint both as recipes** (feeds Rock 3).

## 🪨 Rock 2 — Ship 1.0 (stop deferring the finish line)

It's been "one dry-run away" for weeks. Pair it with a hands-on-at-the-machine
session.

1. **Cold-start dry-run** — reset onboarding on a fresh account, walk the
   wizard, fix every dev-machine assumption. *The last real gate.*
2. **Real donor export** — first live run of the 56 GB streaming/strip path on
   the actual Steam bottle (only unit-tested so far) → `friend-kit.sh`.
3. **Hand a friend the kit → fix what they hit → tag 1.0.**

## 🌱 Ongoing — Grow the moat (recipes)

Only ~5 catalog entries; the intake pipe (Share This Setup) exists but the
catalog is thin. **Every game tuned this month becomes a recipe** — DEATHLOOP,
Mafia 3, SS2, VotV, the two memory-diet titles. The one thing CrossOver can't
out-automate. **Target: ~12 recipes by month end.** Never fake a "Tested:".

## 🧹 Fill-in — polish debts (between the rocks)

- **Last toolbar wedge** — bottle-page pencil/trash still float into the Gamer
  titlebar (same class fixed for Settings in v0.18.0). Finish the cleanup.
- **Website** — version badge stale (`v0.9`), Sikarugir-sourcing line is
  factually wrong, 2.7 MB JS bundle. Wire version to the releases API, fix the
  copy, host on GitHub Pages.
- **Doctor prose es/pt** — the one deliberate localization gap.
- **Feasibility precheck (Smart Bottle)** — the recurring expensive lesson: verify
  a title is even *possible* (framework/runtime it needs, anti-cheat present,
  known-working version) before the user sinks an afternoon. Surface it up front,
  next to the compatibility banner. Grew out of the modern-.NET-app frontier work
  (`docs/wine-quirks.md`, new Doctor rules `coreclr-dotnet-host` / `avalonia-no-surface`).
- **Clonefile bottle duplication** — the prefix is on APFS; `cp -c` clones a
  multi-GB bottle in seconds for ~0 bytes. Route bottle clone / donor export /
  try-on-a-copy through clonefile instead of a full byte copy.
- ✅ **De-Rosetta the codebase (FEX Phase 0)** — *done 2026-08-04.* The
  x86_64-under-Rosetta assumption was hardcoded as string literals in three
  managers; it now lives in one `WineLayout` value (+ a `MachOInfo` host-binary
  reader, the counterpart to `PEInfo`), and `ROSETTA_ADVERTISE_AVX` is set only
  for a translated host. No behavior change — both installed backends detect as
  x86_64. Prerequisite for adopting an ARM64-native Wine if one ships; plan and
  triggers in [FEX-MIGRATION.md](FEX-MIGRATION.md).

## 🅿️ Parked (with reasons — don't chase)

- **#82 newer Apple GPTK** (the EFT-launcher finish): blocked *externally* —
  Apple must ship modern-wine-with-32-on-64; the free build path is dead
  (source has no 32-on-64). Watch, don't build. **Second unlock discovered
  2026-08-04:** FEX translates 32-bit x86 and plugs into Wine's WoW64 as
  `libwow64fex.dll`, so a FEX-era backend retires this without Apple shipping
  anything — see [FEX-MIGRATION.md](FEX-MIGRATION.md) Phase 2.
- **Notarization / auto-update** — 2.0, gated by a paid Developer ID, not
  effort. Bolts on without rework when the goal changes.
- **Absolute Drift / Unity D3DMetal present bug**, **d9vk** — research-grade;
  only if a dull evening wants it.
- **GOG Galaxy / Lutris importers**, **Steam-launched playtime** — additive.
- **True HDR**, **game-native triggers/haptics**, **Steam overlay**,
  **anti-tamper titles** — honest non-goals (no lever / Wine-boundary /
  CrossOver-level). The Doctor already delivers the streaming verdict for the
  last one.

## How we work (keep)

- Build fully — no TODOs. `swift build` + `swift test`; CI enforces both per PR.
- New UI strings get es/pt entries or the localization gate fails the build.
- New wine-spawning helpers MUST call `PrefixRuntimeGate` (one live Wine per
  prefix).
- Ship through `scripts/release.sh`. Versioning: new capability = minor, else
  patch; not every merge needs a release.
- Start Wine-quirk work at [wine-quirks.md](wine-quirks.md); read
  [ARCHITECTURE.md](ARCHITECTURE.md) before touching backend code.
- Hardware/reboot-dependent claims get **live** validation on a real machine.
