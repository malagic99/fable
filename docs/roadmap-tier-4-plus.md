# Fable roadmap — Tier 4 and beyond (Days 59+)

> **Status — 2026-06-26:** v0.5.0-equivalent work ("bulletproof free Steam
> installs") is largely **done on branch `gptk4-heroic-patcher`** but not yet
> tagged — see the status box atop `roadmap-tier-1-3.md`. The structure here
> still holds: **Stage A (Apple Developer ID → signing/notarization/Sparkle)
> remains the hard gate to v0.6 and the real path to v1.0.** That gate has not
> cleared yet, so Stage A is still on hold; near-term work stays in the
> un-gated lanes (Smart Bottle backend auto-pick, Library view, recipe catalog).

Picks up where `roadmap-tier-1-3.md` ends (v0.5.0 shipped). The
structure shifts here: Tier 4 onward is **less prescriptive by design**
because each step depends on external events Fable doesn't control —
Apple Developer ID acquisition, App Store policy, community formation,
hardware availability for streaming, when (or if) a usable open-source
arm64 Wine ships.

The plan groups items into **stages** instead of days, with explicit
gating conditions and rough day estimates per stage. Sequence them
into a calendar once the gates clear.

Three planned releases inside this run:
- **v0.6.0** at end of Stage A (signed + auto-updating)
- **v0.7.0** at end of Stage C (cloud-synced + onboarded)
- **v1.0.0** at end of Stage F (community DB live, app sandbox story
  resolved one way or the other)

---

## Stage A — Distribution sanity (gated on Apple Developer ID)

**Gate:** $99/yr Apple Developer Program enrollment active.

Until this gate clears, Fable users have to right-click → Open + accept
quarantine. Every Tier 1–3 polish item is undermined by that first-run
wart. So this stage gets first priority **as soon as the gate clears**,
ahead of anything else.

| Stage | Scope | Est. days | Notes |
|-------|-------|-----------|-------|
| A1 | Code signing setup: Developer ID Application cert in Keychain, `codesign --deep --options=runtime --sign "Developer ID Application: …"` in `scripts/make-app.sh`. Verify with `spctl -a -v Fable.app` | 1 | Skips the xattr ritual |
| A2 | Notarization: `xcrun notarytool submit` + stapling. `make-release.sh` wraps it. App-specific password lives in Keychain, not in the repo | 2 | First notarization always takes longer than expected |
| A3 | Drop in Sparkle: `Sparkle/Sparkle.framework`, replace Day 16 banner's "Open Release Page" button with an in-place download + install flow. Reuses the existing GitHub releases as appcast source via a feed-generator script | 2 | If Sparkle 3.x integration is rough, fall back to manual download but keep the banner pointing at signed/notarized builds |
| A4 | **Buffer + v0.6.0 release.** Signed, notarized, auto-updating | 1 | |

**Stage A total: ~6 days, but only after the gate clears.**

---

## Stage B — First-launch experience (no gate)

Independent of Stage A — can run in parallel or before.

| Stage | Scope | Est. days |
|-------|-------|-----------|
| B1 | ✅ **Shipped Day 21** (`3b3f134`). First-launch wizard: 4 steps (welcome → source picker → first bottle from template → done). OnboardingState + OnboardingView, en/es localized, "Reset First-Launch Wizard" in Settings. 9 new tests | — |
| B2 | Sample bottle: a small free Windows game (open source — `Hedgewars`, `OpenRA`, `0 A.D. Windows binary`) that demonstrates the full pipeline on first launch | 2 |
| B3 | Tutorial overlays for new users: tooltip coachmarks on first visit to Bottles / Library / Components | 1 |
| B4 | **Buffer.** | 1 |

**Stage B remaining: ~4 days.**

---

## Stage C — Cloud + sync (gated on Stage A)

**Gate:** Stage A complete. CloudKit needs the Developer ID + container
configuration.

| Stage | Scope | Est. days |
|-------|-------|-----------|
| C1 | CloudKit container setup, schema for `Bottle` metadata (without prefix), `Game` records, user preferences. Migration from local-only with conflict resolution | 3 |
| C2 | Sync engine: foreground + background sync, last-write-wins for settings, manual-merge for bottle definitions | 2 |
| C3 | Save sync from Tier 2 Day 39–40 promoted to CloudKit | 1 |
| C4 | **Buffer + v0.7.0 release** (signed + notarized + auto-update + cloud-sync) | 2 |

**Stage C total: ~8 days, gated on Stage A.**

---

## Stage D — Localization expansion (no gate)

Tier 1–3 left this at en + es seed. Adding more is mechanical.

| Stage | Scope | Est. days |
|-------|-------|-----------|
| D1 | French (`fr.lproj`) — high-traffic strings from existing catalog | 1 |
| D2 | German (`de.lproj`) | 1 |
| D3 | Brazilian Portuguese (`pt-BR.lproj`), Simplified Chinese (`zh-Hans.lproj`), Japanese (`ja.lproj`) — done as a batch, sourced from a translator or community PRs once a contribution flow exists | 3 |
| D4 | "Help translate Fable" link in Settings → About; lightweight CONTRIBUTING.md section | 1 |

**Stage D total: ~6 days. Can interleave with anything.**

---

## Stage E — Platform expansion (gated per item)

Each of these is independently gated on a third-party piece of tech
existing in a usable state. Sequence them as the world cooperates.

| Item | Gate | Est. days |
|------|------|-----------|
| Moonlight/Sunshine iPad streaming | Sunshine has a stable macOS host build | 4 |
| Discord server + community Discord RP improvements | (no gate, but pairs with Stage F) | 2 |
| Menu-bar "Now Playing" widget | (no gate) | 2 |
| macOS Focus modes integration ("Gaming" auto-launches Fable) | (no gate) | 2 |
| Vision Pro game streaming | Moonlight visionOS client mature | 4 |
| Native arm64 Wine production support | A widely-usable arm64 Wine build exists (Tier 1 Day 33 was a research scout) | 5 |

**Stage E total: 10–19 days depending on how many gates clear.**

---

## Stage F — Community + compatibility DB (no hard gate)

This is where Fable becomes more than a launcher. Soft gate: enough
users to crowdsource meaningfully. Probably waits until **v0.7.0** is
in the wild for some weeks.

| Stage | Scope | Est. days |
|-------|-------|-----------|
| F1 | Backend selection: Supabase or Cloudflare D1 for a small read-mostly compatibility DB. Auth via GitHub OAuth so submissions have a stable identity | 3 |
| F2 | "Report compatibility" action in BottleDetailView: anonymized bottle.json + game name + works/doesn't + freeform note. Reuses Day 53 "Send Crash Report" pipeline | 2 |
| F3 | Reverse direction: when creating a bottle or registering a game, query the DB for "what works best for this game" — feeds Tier 2 templates with crowdsourced data | 3 |
| F4 | Community installer recipes (Lutris-style): a recipe is a `BottleTemplate` + a script of post-install steps. Recipe registry browsable in-app | 4 |
| F5 | **Buffer + v1.0.0 release.** Localized, signed, cloud-synced, community-aware | 3 |

**Stage F total: ~15 days, soft-gated on adoption.**

---

## Stages without hard gates — utility days

These slot in anywhere there's a calendar gap or a model-swap day.

| Item | Est. days |
|------|-----------|
| Mod manager for one popular title (Stalker, Skyrim) as a test case | 5 |
| Lutris importer (parse `~/.config/lutris` configs) | 2 |
| Telemetry opt-in (privacy-respecting; anonymous launch counts → "Fable saw 47k launches this month" public dashboard) | 3 |
| Per-game launch options presets (Steam launch params syntax compatibility) | 1 |
| Bottle folders / groups for organization | 2 |
| Backup-to-Time-Machine integration helper | 1 |

---

## Flex protocol — Tier 4+ adaptation

The Tier 1–3 protocol still applies: commit at end of every session,
maintain `docs/sprint-log.md`, keep `MEMORY.md` fresh, use `Next:`
lines in commit messages. The differences:

### Gating discipline

- **Don't start a gated stage before the gate clears.** Don't write
  Sparkle integration code before you have the cert. The temptation is
  real; the wasted work is also real.
- **A gate clearing is a planning event, not just a "go" signal.**
  When the Developer ID arrives, dedicate one session to re-planning
  Stage A around what's actually possible (Apple may have changed
  notarization requirements).
- **Keep a "blocked-on-gates" list** at the top of `docs/sprint-log.md`
  so a fresh session model can see what's unblocked vs. waiting.

### Model swap protocol (Tier 4 amendments)

The Tier 1–3 rules carry over with three additions for the longer
horizons here:

1. **Stage transitions are natural model-swap recovery points.** End
   of Stage A is a clean restart spot; the user can spend 5 minutes
   bringing a new session up to speed.
2. **CloudKit, Sparkle, and IGDB API integrations have brittle
   muscle-memory** (which header for which call, etc.). Document the
   real wire-level details in `docs/integrations-notes.md` as you go.
   A future model reading the code alone won't infer them all.
3. **If a less-capable model swaps in for an extended period:**
   pull Stage D (localization) and Stage F4 (recipe collection) work
   forward. Both are high-volume, low-decision work — small models do
   them fine.

### Stop / pivot decisions

Some Tier 4 items might **never ship** because the world changed:

- If macOS gains native Windows-game compatibility at the OS level
  (unlikely but real possibility with Apple Silicon trajectories), the
  whole D3D-translation tier becomes legacy. Pivot Fable to a "Wine
  bottle organizer for legacy workflows" or wind it down with grace.
- If CrossOver's native arm64 Wine becomes free / open-source, much of
  Stage E item "Native arm64" is just an integration day instead of a
  research project.
- If GitHub Sponsors / a Patreon takes off, the gating priority of
  Stage A shifts — paid users justify investing in better distribution
  earlier.

These pivots are decision points, not failures. Catch them at the end
of each stage retrospective.

---

## Rough total

| Stage | Est. days | Calendar weeks at 4/wk | Notes |
|-------|-----------|------------------------|-------|
| A — distribution | 6 | ~1.5 | Gated on Dev ID |
| B — onboarding | 6 | ~1.5 | |
| C — cloud sync | 8 | ~2 | Gated on A |
| D — localization | 6 | ~1.5 | Can interleave |
| E — platforms | 10–19 | ~2.5–5 | Per-item gates |
| F — community | 15 | ~3.5 | Soft gate on adoption |
| Utility days | 14 (max) | ~3.5 | As-needed |
| **Total** | **65–82** | **~16–20 weeks** | **~4–5 months focused, longer with day job** |

So: roughly **v0.5.0 by mid-Tier-3** (end of `roadmap-tier-1-3.md`),
**v0.6.0 within weeks** of Apple Developer ID acquisition, **v0.7.0
~3–4 months after that**, **v1.0.0 when the community DB has real data
in it**. Don't hold any of those dates tightly — the gates dominate.

---

## Update cadence

Both roadmap docs (`tier-1-3` and `tier-4-plus`) get refreshed:

- At each release (v0.3.0, v0.4.0, …) — strike done items, note
  surprises, adjust upcoming estimates based on actual velocity.
- After every model-swap event — verify the plan still makes sense
  with the new capability profile.
- After every major external event — Apple WWDC announcements, GPTK
  updates, Wine/DXMT releases, the user's life calendar changes.

If both files start contradicting each other or feeling stale,
rewrite the affected sections in place — don't accrete addenda.
