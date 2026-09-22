# Fable — Roadmap

> **Status: living document, last updated 2026-09-22 (v0.23.3).**
> A themed plan, not a burndown. Real-game debugging *will* interrupt it —
> that's fine, it has found every important bug so far.
> Supersedes the post-Friend-Kit menu (history in git).

## The governing goal (unchanged)

Fable is a **polished personal tool I share with friends — not a published
product.** No launch, no growth target. **"Done" = boringly reliable in real
use.** **1.0 = a friend is playing on it.** Everything below serves that or is
honestly parked.

## Where we are (v0.23.3, 457 tests, CI green on every PR)

- **Six backends**, flagship Sikarugir (modern Wine + matched D3DMetal): free
  Steam CEF renders, installs self-heal, AAA D3D12 plays. Why:
  [ARCHITECTURE.md](ARCHITECTURE.md). Fix map: [wine-quirks.md](wine-quirks.md).
- **One library** (Wine + native Mac), themes, DualSense raw-HID triggers,
  playtime/notes/health, hardware-aware perf, en/es/pt with a build-breaking
  coverage gate.
- **Fable Doctor**: 28 log signatures incl. the cross-backend "it's the game,
  stream it" verdict, named missing DLLs, and the .NET-Framework / WPF /
  wineserver-collision rules from real debugging. Rules can veto themselves on
  contrary evidence, after one keyed on a Vulkan banner that Wine prints on
  every launch and told healthy D3DMetal bottles to switch backends.
- **Sharing**: `.fablerecipe`, `.fableskin`, `.fbottle` (donor export strips
  games + login, streams with progress + disk preflight), `friend-kit.sh`,
  Send Feedback + Share This Setup (zero-backend GitHub pipes).
- **.NET**: Core (6/7/8) apps run (VotV/YeetPatch verified); the destructive
  `dotnet4x` footgun is guarded; real .NET Framework 4.8 installs on the GPTK
  backend (32-on-64) — see [DOTNET-FRAMEWORK-LAUNCHERS.md](DOTNET-FRAMEWORK-LAUNCHERS.md).

---

## 🪨 Rock 1 — Memory Diet — **shipped (v0.23.0–v0.23.1)**

The STALKER 2 / TLOU2 unified-memory bleed: AAA ports budget against separate
RAM+VRAM pools, but on a 24 GB Mac that's one pool D3DMetal double-counts, so
streaming caches grow toward a budget that doesn't physically exist → wired-
memory crash. Two Fable-shaped pieces:

1. ~~**Engine.ini streaming-pool cap writer**~~ — shipped v0.23.0 as a
   reversible per-game toggle.
2. ~~**Memory-pressure nudge**~~ — shipped v0.23.0 (`MemoryPressureMonitor`),
   plus DXVK VRAM honesty in v0.23.1.
3. **Recipes from it** — S.T.A.L.K.E.R. 2 minted (v0.23.2); TLOU2 still
   unverified. Getting S.T.A.L.K.E.R. 2 rendering took a separate fix: only
   Sikarugir's `d3d12.so` was missing the rpath that lets it reach
   D3DMetal.framework, so D3D12 titles died at adapter creation while D3D11
   ones were fine (v0.23.3).

## 🪨 Rock 2 — Ship 1.0 (stop deferring the finish line)

1. ~~**Cold-start dry-run**~~ — **done (2026-09-22).** It found a real one:
   onboarding recorded completion in UserDefaults, which outlives deleting both
   Fable.app and Application Support, so a clean install read back "already
   onboarded" and skipped first-run setup entirely. Completion now lives beside
   the app's own data. Fixed in v0.23.3.
2. ~~**Real donor export**~~ — **parked.** Deliberately skipped rather than
   pretended: the 56 GB streaming/strip path stays unit-tested only. Revisit if
   a friend actually needs a donor bottle.
3. **Hand a friend the kit → fix what they hit → tag 1.0.** *The remaining
   gate* — and by this project's own definition ("1.0 = a friend is playing on
   it"), the only one that can close it.

## 🌱 Ongoing — Grow the moat (recipes)

Only ~5 catalog entries; the intake pipe (Share This Setup) exists but the
catalog is thin. **Every game tuned this month becomes a recipe** — DEATHLOOP,
Mafia 3, SS2, VotV, the two memory-diet titles. The one thing CrossOver can't
out-automate. **Target: ~12 recipes by month end.** Never fake a "Tested:".

## 🧹 Fill-in — polish debts (between the rocks)

- **Last toolbar wedge** — bottle-page pencil/trash still float into the Gamer
  titlebar (same class fixed for Settings in v0.18.0). Finish the cleanup.
- ~~**Website version badge**~~ — **done (2026-09-22).** Both version sites now
  carry `data-fable-version` and are refreshed from the GitHub releases API, so
  a release no longer needs a hand-edit. Still open on the same page: the
  Sikarugir-sourcing line is factually wrong, and it's a 2.7 MB single-file
  bundle whose unpacker already errors in console (pre-existing; the page
  renders anyway).
- **Doctor prose es/pt** — the one deliberate localization gap.
- **Dependency detection is presence-only for everything except VC++.** The
  Visual C++ entries now check the registry key a real install writes, because
  Wine ships its *own* builtin `msvcp140.dll` — so the old file check was true
  on every prefix from creation and Fable never installed the runtime at all.
  The other catalog entries still detect by file and may have the same blind
  spot wherever Wine provides a builtin of the same name. Worth an audit.
- **Windows version can silently block a redist.** A bottle left on Windows 7
  (some winetricks verbs set it) makes the VC++ 2022 installer a no-op, with no
  error surfaced anywhere. Either pin the version before installing a redist or
  have the Doctor notice the mismatch.
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
