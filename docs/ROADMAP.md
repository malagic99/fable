# Fable — Development Roadmap

> **Status: living document, last updated 2026-07-03 (v0.13.5).**
> Supersedes `roadmap-tier-1-3.md` and `roadmap-tier-4-plus.md` (both retained
> as history — their day-by-day grids were overtaken by the Sikarugir/D3DMetal
> breakthrough and no longer describe the plan).

## The governing goal (unchanged)

Fable is a **polished personal tool I share with friends — not a published
product.** There is no launch, no deadline, no growth target. Distribution
(notarization, code-signing, auto-update, an App Store/DMG story) stays
**parked indefinitely** and is not on this roadmap by choice.

**"Done" = boringly reliable in real use.** Version numbers just track state.
We are explicitly *not rushing to finish* — this roadmap is a menu to pull from
when the mood strikes, ordered by value, not a schedule to burn down.

---

## Where we are (v0.13.5)

A free macOS Wine wrapper that plays Windows games — and now native Mac games —
from one cover wall. **DualSense adaptive triggers now work reliably while the
game is frontmost** (raw-HID bypass, v0.13.5).

- **Six graphics backends**, flagship **Sikarugir** (modern Wine + D3DMetal):
  free Steam CEF renders, installs, and plays AAA D3D12 titles on Apple Silicon.
- **One library, everything in it:** Wine games, Steam/Epic/GOG/Heroic imports,
  and **native macOS games** (native-Steam import + any `.app`).
- **Identity you own:** themes as shareable `.fableskin` files (Fable, Midnight,
  Pitch Black, OG Steam), light/dark, custom backgrounds, custom covers — and
  (as of v0.13.2) the wash reaches the classic Form views too.
- **Two faces:** Classic (bottles-first utility) and Gamer (Big-Picture cover
  wall).
- **Trust, honestly earned:** confidence dots from real recipe/quirk data,
  Fable Doctor, self-healing stability layer, cover-art pipeline.
- **DualSense adaptive triggers:** static user profiles (Feedback, Weapon,
  Vibration modes), per-bottle or per-game. Raw-HID writes bypass the framework
  gate that was silencing them when the game took focus; a 1s keep-alive
  re-asserts the profile so any clear is restored within a second.
- **348 source files, 348 tests / 81 suites.** Ship ritual: branch → PR →
  squash-merge → realign `gptk4-heroic-patcher` → tag → `ditto` zip → release.

---

## Lane 1 — Harden & verify ✔ (swept 2026-07-03, v0.13.6)

Real-world testing has caught every important bug so far. All five items are
now closed or as closed as they can be without a reboot-and-play session.

1. **✔ Trigger resistance survives game focus (v0.13.5).** Confirmed live — the
   raw-HID path carries the profile forward while the game is frontmost, and the
   1s keep-alive re-asserts it if anything clears it. The framework's background
   write gate is bypassed. See [[fable-dualsense-triggers]].
2. **✔ Shader-cache restore mechanics (v0.13.6).** Simulated a purge of a live
   wine Metal cache → Fable's startup restore healed it byte-identical from the
   snapshot. Cache dirs are keyed by GPU + driver build (`16777235_467`), not
   the boot session, so a plain reboot shouldn't invalidate them. *Open tail:*
   the no-stutter-after-real-reboot feel test — one warmed game, one reboot,
   one play session.
3. **✔ D3DMetal onboarding step, seen live (v0.13.6).** Wizard reset + relaunch:
   detects the installed D3DMetal, shows the ready state, steps advance
   correctly. Cosmetic: version prints as "10.0_4" (raw string underscore).
4. **✔ Z: drive self-heal — no recurrence.** Zero "can't find Z:" lines in any
   log since the heal shipped; `z:` symlink healthy. Closed as monitored; log
   capture stays in place if it ever recurs.
5. **✔ Native-Steam cold-start handoff (v0.13.6).** From a fully cold Steam,
   `steam://rungameid/` starts the client, auto-logs-in, and processes the
   launch in ~30 s. *Finding fixed in v0.13.6:* stale manifests (files deleted
   outside Steam — a husk dir with just a .DS_Store) made Steam fail silently;
   the import list now verifies files exist on disk before offering a game.

## Lane 2 — The moat: recipes + the Friend Kit

The one thing no free wrapper has is *curated, honest per-game setups*. This is
where "boringly reliable" is actually won.

6. **Grow the recipe catalog.** Still only **3 built-in recipes** (Balatro,
   DEATHLOOP, System Shock 2). Every title personally tuned — Ready or Not,
   Mafia III, Absolute Drift, Subnautica, … — should become a `GameRecipe` or a
   shareable `.fablerecipe`. **Never fake a "Tested:" entry** — a wrong green is
   worse than no dot.
7. **The Friend Kit** — the literal finish line of the goal. Assemble a share
   bundle: the Fable zip + a donor `.fbottle` Steam bottle + the `.fablerecipe`
   set + a one-page README (the right-click→Open ritual, the Sikarugir link).
   Dry-run the first-run wizard as a "friend" (reset onboarding / fresh account)
   so the cold-start path is proven before anyone receives it.
8. **Recipe authoring from the app.** Turn a bottle/game the user just tuned into
   a `.fablerecipe` with one click (capture backend + perf + verbs + args), so
   the catalog grows as a byproduct of playing.

## Lane 3 — Quality-of-life polish

Small, additive, low-risk. Pull when a rough edge annoys.

9. **✔ Native games in the Classic Library (v0.14.0).** One wall serves both
   faces.
10. **✔ Per-game notes + playtime/last-played (v0.15.0).** History block in the
    inspector; notes in Tune. Sorting the wall by recent remains a follow-on.
11. **✔ Bulk cover refresh (v0.15.0).** Wall ⋯ menu → Fetch Missing Covers.
    Also fixed: custom covers persist across relaunches (Steam tile), and wall
    grouping shipped (Platform / Health / Bottle-as-account).
12. **Theme editor in-app.** Author a `.fableskin` from a color-picker sheet
    instead of hand-editing JSON — the export path already exists.
13. **Trigger keep-alive tuning surface.** If the 1s interval ever fights a
    title, expose it (or an auto-off "let the game own triggers" toggle) rather
    than hard-coding.

## Lane 4 — New surfaces (optional, when curious)

14. **More library sources.** GOG Galaxy and Lutris importers, mirroring the
    Heroic import already in place.
15. **✔ Playtime tracking (v0.15.0).** Fable-launched sessions tally real
    time; Steam-launched games now also show as running (windows-path match).
16. **✔ Localization (v0.16.0).** en/es/pt + in-app language switch (Settings →
    Appearance). Long-form footers/help still English — the remaining tail.

## Lane 5 — Explicitly parked (honest reasons, don't chase)

- **Distribution / notarization / signing / auto-update.** Parked by the goal.
- **Steam overlay (Shift-Tab).** Injects and runs but composites black — a
  CrossOver-level cross-process CEF/GPU-shared-texture problem on D3DMetal, not
  a Fable-level fix. Controller config works from the main Steam window without
  it.
- **True HDR pipeline.** No honest lever in SwiftUI/D3DMetal to drive
  extended-range output; Pitch Black gives real black on OLED/HDR panels, which
  is the part we *can* deliver. Don't fake an "HDR" toggle.
- **The game's *own* contextual triggers/haptics.** Under Wine the game's Sony
  SDK / Windows.Gaming.Input calls don't execute, so there's no intent to
  mirror — static user profiles are the ceiling. See [[fable-dualsense-triggers]].
- **First Light and kin.** Packed-exe protectors int3-fail-fast under every
  macOS Wine backend; the answer is streaming, not a backend.
- **CrossOver's 20-year fix database.** Unwinnable on long-tail breadth; we win
  on architecture parity + automation + diagnostics instead.

---

## How we work (keep)

- Build fully — no TODOs, no stubs. `swift build` + `swift test` after changes.
- GUI-first; terminal only as a debug fallback.
- Ship every change through the ritual; About reads the bundle version.
- Start any Wine-quirk work at `docs/wine-quirks.md`.
- Hardware- and reboot-dependent claims get **live** validation on the user's
  machine before they're trusted — the lab isn't enough.

## If you only pull three things next

1. **Turn two more real games into recipes** (Lane 2.6) — the moat compounds.
   Absolute Drift and Ready or Not would be solid next candidates.
2. **Assemble a first Friend Kit and cold-start it** (Lane 2.7) — that's the
   goal, made tangible. A fresh account through the onboarding wizard, a
   preloaded Steam bottle, and the recipe set.
3. **The one Lane 1 tail:** after the next real reboot, launch a warmed game
   and feel for first-run stutter — that's the final word on shader-cache
   reuse (Lane 1.2).
