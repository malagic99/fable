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

## Lane 1 — Harden & verify (highest value, do first)

Real-world testing has caught every important bug so far. Closing these beats
any new feature. Each is a *confirm-or-fix*, not a build.

1. **✔ Trigger resistance survives game focus (v0.13.5).** Confirmed live — the
   raw-HID path carries the profile forward while the game is frontmost, and the
   1s keep-alive re-asserts it if anything clears it. The framework's background
   write gate is bypassed. See [[fable-dualsense-triggers]].
2. **Shader-cache reuse across reboot.** Does Metal actually *reuse* a restored
   D3DMetal pipeline cache after a reboot, or recompile anyway (cache-key
   stability unknown)? Warm a game → reboot → relaunch → is first-run stutter
   gone? If not, the feature is a benign no-op that needs a rethink.
3. **D3DMetal onboarding step, seen once.** It has never been observed live
   (existing install has `onboarding.hasCompleted = true`). Dry-run via
   `OnboardingState.reset()` or a fresh account before trusting it.
4. **Z: drive self-heal root cause.** Shipped without a confirmed log line; if
   "can't find Z:" recurs, capture the actual wine log line and pin the cause.
5. **Native-Steam launch reliability.** `steam://rungameid/` hands off to the
   native client — confirm it launches (and focuses) reliably from a cold Steam.

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

9. **Native games in the Classic Library.** Today they're Gamer-wall only; the
   classic Library is still Wine-only. Unify so both faces show everything.
10. **Per-game notes / "last played".** A tiny freeform note and a last-launched
    timestamp per game — sorting the wall by recent is a natural follow-on.
11. **Bulk cover refresh.** A "refresh all missing covers" action; today it's
    per-tile.
12. **Theme editor in-app.** Author a `.fableskin` from a color-picker sheet
    instead of hand-editing JSON — the export path already exists.
13. **Trigger keep-alive tuning surface.** If the 1s interval ever fights a
    title, expose it (or an auto-off "let the game own triggers" toggle) rather
    than hard-coding.

## Lane 4 — New surfaces (optional, when curious)

14. **More library sources.** GOG Galaxy and Lutris importers, mirroring the
    Heroic import already in place.
15. **Playtime tracking.** Fold the activity monitor's start/stop into a simple
    per-game playtime tally.
16. **Localization beyond en/es.** The scaffold + `L10n` helper exist; adding a
    language is now mostly translation, not plumbing.

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
3. **Verify the other Lane 1 unknowns** — shader-cache reuse across a reboot
   (Lane 1.2), the D3DMetal onboarding step live (Lane 1.3), Z: drive root
   cause (Lane 1.4), native-Steam launch reliability (Lane 1.5).
