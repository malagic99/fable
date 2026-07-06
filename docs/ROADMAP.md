# Fable — Development Roadmap

> **Status: living document, last updated 2026-07-06 (v0.20.0).**
> Supersedes `roadmap-tier-1-3.md` and `roadmap-tier-4-plus.md` (retained as
> history). The five-lane plan that used to live here is done — Lane 1 swept,
> the UI review series shipped, the Friend Kit shipped. This is the post-kit
> roadmap.

## The governing goal (unchanged)

Fable is a **polished personal tool I share with friends — not a published
product.** No launch, no deadline, no growth target. **"Done" = boringly
reliable in real use.** This roadmap is a menu ordered by value, not a
schedule to burn down.

## Where we are (v0.20.0)

Everything the original plan called for exists and is tested (398 tests,
CI-enforced on every PR):

- **Six backends**, flagship Sikarugir (modern Wine + matched D3DMetal): free
  Steam CEF renders, installs self-heal, AAA D3D12 plays. The why lives in
  [ARCHITECTURE.md](ARCHITECTURE.md); the fix map in [wine-quirks.md](wine-quirks.md).
- **One library** (Wine + native Mac games), themes, DualSense raw-HID
  triggers, playtime/notes, hardware-aware performance, three languages with
  a build-breaking coverage gate.
- **Fable Doctor**: 20 log signatures, named missing DLLs, and the
  cross-backend verdict ("same int3 on two backends ⇒ it's the game —
  stream it").
- **Sharing formats**: `.fablerecipe`, `.fableskin`, `.fbottle`
  (export streams with progress + disk preflight; import adopts with fresh
  identity), `scripts/friend-kit.sh`, and two zero-backend GitHub pipes
  (Send Feedback, Share This Setup).

## 1.0 — a friend is playing (days, not weeks)

1. **Cold-start dry-run**: reset onboarding on a fresh account, walk the
   wizard, fix any dev-machine assumption. *The last real gate.*
2. **Export the donor Steam bottle** into `kit-payload/`, run
   `friend-kit.sh`, hand the zip over.
3. Fix whatever the first friend actually hits. Then it's 1.0 — the version
   number finally matching the goal.

## 1.x — the menu (pull when the mood strikes)

- **Recipe catalog growth** — the moat. Intake is built (Share This Setup →
  `[Recipe]` issues); convert honest reports into `GameRecipeCatalog` lines.
  Never fake "Tested:".
- **More game testing** — every real session either grows the catalog or
  feeds the Doctor a new signature.
- **Doctor prose localization** (deliberate gap — [LOCALIZATION.md](LOCALIZATION.md)).
- **Bottle-page toolbar wedge** — last `.toolbar`-in-Gamer-face offender
  (same fix pattern as the Settings pills, v0.18.0).
- **Playtime for Steam-launched games** — needs poll-based session tracking;
  weigh against the rubber-mat policy (never compete with a running game).
- **Theme editor in-app** — author a `.fableskin` from a color-picker sheet;
  the export path already exists.
- **More library sources**: GOG Galaxy, Lutris (mirror the Heroic importer).
- **Steamworks redist pre-install** at Steam-bottle setup (kills the
  download-scheduler starvation case).
- **Wall sort by recently played** — the data exists in GameStatsStore.

## 2.0 — the money gate

- **Apple Developer ID → notarization → Sparkle auto-update.** The only item
  gated by a purchase rather than effort. Kills the right-click→Open ritual
  and makes the update banner one-click. Everything is structured so this
  bolts on without rework.

## Honest non-goals (don't chase, don't fake)

- **True HDR** — no honest lever in SwiftUI/D3DMetal for extended-range
  output; Pitch Black gives real OLED black, which is the deliverable part.
- **The game's own contextual triggers/haptics** — Sony SDK calls don't
  execute under Wine; static user profiles are the ceiling.
- **Steam in-game overlay** — cross-process CEF GPU texture fails on
  D3DMetal; CrossOver-level Wine work. Controller config works from the main
  Steam window.
- **Anti-tamper titles (First Light and kin)** — identical int3 on every
  backend including CrossOver; the Doctor now delivers the streaming verdict
  automatically.
- **CrossOver's 20-year fix database** — unwinnable on breadth; Fable wins on
  architecture parity + automation + diagnostics instead.

## How we work (keep)

- Build fully — no TODOs, no stubs. `swift build` + `swift test` after
  changes; CI enforces both on every PR.
- New UI strings get es/pt entries or the localization gate fails the build.
- GUI-first; terminal only as a debug fallback.
- Ship through `scripts/release.sh`. Versioning: new capability = minor,
  everything else = patch; not every merge needs a release.
- Start any Wine-quirk work at [wine-quirks.md](wine-quirks.md); read
  [ARCHITECTURE.md](ARCHITECTURE.md) before touching backend code.
- Hardware- and reboot-dependent claims get **live** validation on a real
  machine before they're trusted — the lab isn't enough.
