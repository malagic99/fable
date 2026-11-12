# Fable — Roadmap

> **Status: living document, last updated 2026-11-12 (v1.2.0).**
> A themed plan, not a burndown. Real-game debugging *will* interrupt it —
> that's fine, it has found every important bug so far.
> Earlier versions of this page (the three "rocks" up to 1.0) are in git.

## The governing goal

Until 1.0 the goal was *a polished personal tool shared with friends*, and
**1.0 = a friend is playing on it**. That happened on 2026-09-22.

The goal now: **be the honest Mac game layer, and launch it publicly.**
Fable should know which runtime each bottle uses, prove that runtime is
intact, and say how sure it is that a setup works — and never claim more than
that. "Done" still means boringly reliable in real use. The road there is the
Runtime Integrity & Compatibility Lab (FRICL), one slice per release.

*This goal was inferred from the launch and FRICL conversations of November
2026, not written by the owner. Correct it here if it's wrong.*

## Where we are (v1.2.0, 620 tests, CI green on every PR)

- **Seven backends.** Flagship Sikarugir (Wine 10 + matched D3DMetal): Steam's
  client renders, AAA D3D12 plays. Sikarugir 11 (Wine 11) for newer Denuvo
  games, recipe-only until more games are confirmed. A dedicated installer
  engine for 32-bit installers. Why: [ARCHITECTURE.md](ARCHITECTURE.md). Fix
  map: [wine-quirks.md](wine-quirks.md).
- **Setup needs no Terminal.** Engines are checksum-pinned downloads, Rosetta
  is installed from the wizard, `cabextract` and `innoextract` ship in the
  app. Not yet proven on a Mac that never had Homebrew or Rosetta.
- **Runtime identity.** Each bottle records and keeps its engine version
  (`BottleRuntime`), with a backed-up, explicit move to a newer one.
- **Evidence-based labels.** Verified only on the backend a recipe was tested
  on; play time counts per engine; the reason is shown beside the label.
- **Provenance.** Each build records its source commit; each release ships
  its checksum and build record.
- **Native Steam bridge** (experimental, since v1.0.3): Windows games in a
  Sikarugir bottle talking to the Mac Steam client. Built on the user's Mac,
  which still needs Homebrew. Plan: [NATIVE-STEAM-BRIDGE.md](NATIVE-STEAM-BRIDGE.md).
- **One library** (Wine + native Mac), themes, DualSense triggers,
  playtime/notes/health, hardware-aware performance, en/es/pt with a
  build-breaking coverage gate.
- **Fable Doctor** log signatures, the anti-cheat list, and sharing formats
  (`.fablerecipe`, `.fableskin`, `.fbottle`).
- **Licence:** GPL-3.0-only since v1.1.1.

---

## 🧭 The road to FRICL

One slice per release. Each one must leave working bottles alone.

| Release | Slice | State |
|---|---|---|
| **v1.2** | Runtime identity and pinning; no-Terminal setup; evidence-based labels; provenance | **Shipped 2026-11-12** |
| **v1.3** | Integrity manifests; the first canaries (D3D12 through D3DMetal first) | **Next** |
| **v1.4** | Undo and recovery for bottle and engine changes | Planned |
| **Later** | Community recipes as real-game evidence; Lab screen; command-line tool | When run history justifies them |

### v1.3 — prove the runtime

1. **Integrity manifests.** When an engine is installed and assembled, record
   every file's hash, every symlink's target, and what it was assembled from.
   Verify on demand and before a move to a newer engine. The catalog
   (`versions.json`) stays the list of what can be downloaded; a manifest
   describes what is actually on disk.
2. **Canaries.** Small test programs run in a throwaway prefix, never in a
   user's bottle, climbing the validation ladder: Wine starts → a Windows
   program runs → the intended renderer DLLs load → a D3D device is created.
   Results are Passed / Failed / Skipped / Unsupported / Inconclusive, and
   **Skipped is never Passed.**
3. **Where the results show.** "Move to Newer Engine…" runs the canary on the
   new engine first. Labels gain a level between "untested" and "played":
   the runtime is validated, the game isn't.

4. **Benchmark (proposed 2026-11-12).** A canary that draws frames is most
   of a benchmark: the same throwaway prefix, the same test program, timed.
   Two different tools share that name, and only the first belongs here:
   - *Engine benchmark.* One fixed D3D12 scene, run on an engine, reporting
     frame times. It answers "is the new engine slower than the one I'm on,
     on this Mac" before a move, and catches a regression across engine or
     macOS updates. Synthetic, so it never claims a game's performance.
   - *In-game capture.* Frame times recorded while a real game runs, filed
     with the engine, chip and settings. This is the per-chip recipe
     evidence of the old Sprint 2 plan, and it is rung 7 — people, not CI.
   Build the engine benchmark after the device-creation canary; it needs the
   frame-present rung, which that canary doesn't reach.

**Status (2026-11-12):** manifests are built — recorded at install, adopted
for engines already on disk, checked from the bottle page and before a move.
The developer-tools gap below was fixed in v1.2.1.

### Fixed in v1.2.1: engine assembly needed Apple's developer tools

Assembling an engine called `otool` and `install_name_tool`, which are stubs
on a Mac without Xcode's Command Line Tools. The Wine 10 path ignored the
failure, leaving an engine that installed and couldn't create a D3D12 device.
`MachORpath` now does it in Swift, byte-identical to Apple's tool on the real
engine files. Never reproduced on a Mac without the tools — and exactly the
fault the device-creation canary exists to catch.

### How the parked items fit

They are not side quests; each is a later consumer or a source of evidence.

- **Smart Doctor** is FRICL's "Game Doctor reads evidence" step with a model
  on top. It needs what v1.3 produces: a case file is only as good as the
  facts in it, and "which engine, is it intact, did the canary pass on it"
  are the facts a rule or a model can't get from a log. Order: the rule
  engine reads identity and canary results (v1.3–v1.4); the on-device and
  cloud tiers come after, in "Later". Its community-fix sharing is the same
  thing as FRICL's community recipes — real-game evidence, rung 7 of the
  ladder — so build it once.
- **Installer follow-ups.** The installer engine is a runtime like the
  others, and v1.3 should treat it as one: it gets a manifest, and it gets
  its own canary (a 32-bit program runs — the failure the engine exists to
  avoid). The untested cases (old Inno Setup, repack unpackers) are
  real-installer evidence and go in the compatibility record with a result
  each, not into a "works" claim. The install-coalescing follow-up is done
  for the Wine 10 and 11 engines; the developer-tools dependence is the gap
  above.
- **History handbook.** The written record of how each hard failure was
  found is the canary backlog. Each entry names a fault a check should catch
  from now on: the renderer libraries that had to stay symlinks (manifest:
  symlink targets), the missing `d3d12.so` rpath (canary: device creation),
  the `dxgi` break on Wine 11 (canary: DLL load), the app that only launched
  on the build Mac (clean-Mac test). Write it as that list, with the check
  beside each story, and it stops being a memoir.

### Ground rules (unchanged)

- **A failed canary blocks an engine *update*, never a game that already works.**
- **The top of the ladder is people, not CI.** Frame-present and real-game
  evidence come from real Macs. A canary result never claims "Tested:".
- **Evidence over verdicts.** Every label can say why.

### Launch track (runs beside the slices, waits on the owner)

- **Name and logo.** The rename can't start until a name is chosen.
- **Signing and notarization.** Needs a paid Apple Developer account. Until
  then a download needs the quarantine flag cleared by hand.
- **D3DMetal sourcing.** Fable never hosts Apple's framework; it arrives
  inside Sikarugir's template download. Decide whether that is acceptable
  for a public launch.
- **Data licence** for recipes and evidence (CC BY-SA was the suggestion).
- **Clean-Mac test** of setup with no Homebrew and no Rosetta.

## 🌱 Ongoing — grow the recipe catalog

Eight catalog entries. The intake pipe (Share This Setup) exists but the
catalog is thin. Every game tuned becomes a recipe, on the backend it was
actually tested on. Never fake a "Tested:".

## 📎 FRICL in full (reference)

*Adopted 2026-11-11 as a north star, not a sprint plan.* Built from the proposal
"Fable Runtime Integrity & Compatibility Lab".

Fable should **know** which runtime each bottle uses, **prove** that runtime is
intact, and **say how sure it is** that a setup works. "Installed" is not
"working", and a version string is not proof of compatibility. A bottle
manager that only pairs a prefix with whatever Wine is installed can't do
this. That is the gap this direction closes.

Four capabilities, in this order:

1. **Runtime identity and pinning.** Each bottle records which engine and
   renderer it uses (with a schema version) and a policy: pinned, follow the
   default, or managed. **Shipped in v1.2** as `BottleRuntime` (pinned or
   follow-newest).
2. **Integrity manifests.** Record hashes and layout for each installed engine
   and renderer, checked before launch. Build them from what already exists:
   SHA-pinned downloads in `versions.json`, staged and atomic installs in
   `ComponentManager`, and the assembly markers.
3. **Compatibility canaries.** Run in disposable prefixes (APFS clones) and
   climb a validation ladder:
   - starts
   - `wineboot`
   - DLL resolution
   - device creation
   - frame present
   - a real game

   Results are Passed / Failed / Skipped / Unsupported / Inconclusive.
   **Skipped is never Passed.** **Test D3D12 through D3DMetal first and D3D11
   second.** That is where Fable's real failures have been: the `dxgi` ABI
   break on Wine 11 and the renderer libraries that had to stay symlinks. The
   mingw toolchain from the installer work can build the canary executables.
4. **Targeted recovery.** Repair or roll back one component as a transaction.
   This comes last, once there is run history showing what actually needs
   recovering.

The Lab UI and a CLI come after all four.

**Ground rules**
- **A failed canary blocks an engine *update*, never a game that already works.**
  The lab exists to remove friction, not add it.
- **The top of the ladder is people, not CI.** Frame-present and real-game
  evidence can't run on hosted Mac runners. It comes from real Macs: yours,
  friends', and later community recipes. A canary result never claims "Tested:".
- **Confidence labels:** known-good, validated runtime, plausible, experimental,
  unsupported. Smart Bottle and the Doctor read them through the compatibility
  database.

**How it rides the existing pipeline:** it is not a separate track. Each release
carries a slice:
- **v1.2** — runtime identity and pinning. It lands before the Homebrew-free
  engine work starts switching engines.
- **v1.3** — manifests and the first canary, with canary evidence stored in the
  versioned compatibility database next to performance capture.
- **v1.4** — undo for "no-magic mode", which is a lightweight form of recovery.
- **Later** — community recipes become real-game evidence, and the Lab UI and
  CLI are built when run history justifies them.

## 🧹 Fill-in — polish debts

*Carried over from the v0.23.3 roadmap and not re-audited since; some may
already be done.*

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
- **Let backend selection see the hardware.** `SmartBackendSelector` already
  auto-picks from a validated recipe, then from directory markers — but it never
  consults `HardwareProfile`, which already knows the chip and unified memory
  and is currently used only for performance presets. The gap isn't building
  auto-selection, it's letting the thing that picks a backend see the machine
  it's picking for. Caveat worth keeping: a confident wrong pick is worse for a
  confused user than a visible choice, because it reads as Fable being broken
  rather than a setting to change. Auto-pick where it's *sure* (recipe, or a
  decisive marker); otherwise leave a sane default rather than guessing from
  specs alone.
- **Shrink the backend picker to what this Mac can use.** Six entries with names
  like `DXVK + vkd3d` and `Apple GPTK (legacy, Wine 7.7)` are a wall the moment
  a non-technical user opens the menu — and even perfect auto-selection leaves
  that list sitting there. Hiding backends whose components aren't installed,
  or that this hardware can't benefit from, removes more confusion than smarter
  picking does. Pairs with the item above; do them together.
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
- **007 First Light recipe**, **Smart Doctor** (an optional local model
  behind the Doctor), the **installer follow-ups** (old Inno Setup and repack
  unpackers on the installer engine) — parked by the owner in November 2026.
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
