# Fable roadmap — Tiers 1 → 3 (Days 21–58)

Day-by-day plan covering all of Tier 1 (strategic), Tier 2 (major QoL),
and Tier 3 (diagnostics). Designed for a working pace of ~1 productive
session per day. Numbered days are the headline scope; lettered days
(21a, 21b…) are buffer/checkpoint slots that exist whether or not we
need them — see "Flex protocol" at the end.

Three planned releases inside this run: **v0.3.0** at end of Tier 1,
**v0.4.0** at end of Tier 2, **v0.5.0** at end of Tier 3.

---

## Tier 1 — Strategic unlocks (Days 21–36)

### Bottle export / import — the foundation other tiers reuse

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **21** | `BottleArchive` utility: tar+zstd a bottle directory (prefix + bottle.json) to a `.fbottle` file, with a manifest carrying Fable version + Wine version + checksum | Manifest contract pins the format before downstream tiers depend on it |
| **22** | Import flow: drop `.fbottle` on Fable → validates manifest, rewrites absolute prefix paths in `system.reg`, registers as new bottle | Path rewriting is the risky bit — earlier is better |
| 22a | **Buffer.** Real-world test: export Steam bottle on this Mac, import on a second machine if available; otherwise simulate by exporting and re-importing locally to a different bottle id | |
| **23** | UI: "Export Bottle…" toolbar action, "Import Bottle…" in BottleListView menu, progress sheet (compression can take minutes on a 30 GB bottle) | |

### Custom Wine builds + per-bottle Wine pinning

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **24** | Extend `ComponentManager` so a user can drop a `.tar.xz` / `.tar.gz` of a custom Wine build on the Components view; it's verified, named ("Wine ProtonGE-9-21"), and registered | Single biggest compatibility unlock |
| **25** | Add `Bottle.wineComponentID: String?` (nil = use default); update `WineManager.wineBinary(for: bottle)` to honor it; per-bottle Wine picker in `BottleDetailView` | |
| 25a | **Buffer.** Test with at least two custom builds (one wine-tkg, one CrossOver-derived if accessible). Document any builds that need extra dylib paths | |
| **26** | Component cleanup UI: orphaned Wine versions (no bottle references) get a "Delete unused" action. Disk usage rolls these in | Without this, Components view becomes a graveyard |

### Heroic / GOG Galaxy library bridge

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **27** | Reverse-engineer Heroic's `~/Library/Application Support/Heroic/store_cache/library.json` schema; write a parser that returns `[HeroicGame]` | The schema is the unknown; do it before building UI on top |
| 27a | **Buffer / model checkpoint.** Commit the parser + a fixture-based test suite even if UI isn't done. This is a natural pause point if a session needs to end mid-feature | |
| **28** | "Import from Heroic…" sheet: lists games, lets the user multi-select, creates one bottle per game (Steam Ready template by default), symlinks the installed exe into `drive_c` | Reuses Day 14 templates and Day 15 game registration |
| **29** | Same shape for GOG Galaxy if installed (`~/Library/Application Support/GOG.com/Galaxy/storage/galaxy-2.0.db` — SQLite). Skip if user doesn't have it; the feature is additive | |

### Cross-bottle Library view

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **30** | New sidebar entry "Library" between Bottles and Components; flat list of every `Game` across every `Bottle` with backlinks | Architecture is straightforward; the value is huge |
| **31** | Sort + filter: by recent-played (uses `lastExitCode` timestamps — add `lastLaunched: Date?` to Game), name, bottle, backend. Search bar | |
| 31a | **Buffer.** Polish pass + screenshots for the v0.3.0 release notes | |
| **32** | Cover art *placeholder*: extract a higher-resolution icon than the menu-bar one (PE has multiple icon sizes — use the largest). Real cover art comes in Tier 2 with IGDB | |

### ARM64 Wine experiments

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **33** | Research dive: which open-source Wine builds (if any) ship native arm64 macOS binaries by then; if Apple's GPTK 5+ ships native arm64 wine, document the import path | This is a research day, not implementation. Result might be "nothing usable yet, parking it" |
| 33a | **Buffer.** If something usable exists, extend the custom-Wine-build flow from Day 24 to declare its `architecture: arm64 / x86_64`. Per-game launches route accordingly | |
| **34** | If nothing's available: write the abstraction (`GameLauncher.wineFor(architecture: PEInfo.Architecture)`) so it's ready the day a usable arm64 build ships. Test with mocked binaries | Even if shippable feature is delayed, the architecture lands |

### Tier 1 close-out

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **35** | Stabilization day: fix anything Tier 1 testing surfaced, update CHANGELOG, refresh memory files | |
| **36** | **Release v0.3.0** off `dev` → `main`. Build zip, write release notes, post tag. Memory file gets a roadmap update | |

---

## Tier 2 — Major QoL (Days 37–47)

### Cover art + metadata

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **37** | IGDB API integration: client credentials flow, search by name, cache `cover_url + summary + release_year + genres` in `Bottles/<id>/metadata/<gameID>.json` | API key needs to live in user defaults (Settings → API Keys), not hardcoded |
| **38** | Library view (Day 30) renders covers when available; fall back to extracted icon, then SF Symbol. "Refresh metadata" per-game action | |
| 38a | **Buffer.** IGDB rate-limit handling + a "metadata source" picker if we want to allow alternatives (SteamGridDB has nicer art) | |

### Save backup + restore

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **39** | `SaveGameLocator` walks known patterns (`Documents/My Games/*`, `Saved Games/*`, `AppData/LocalLow/*/<publisher>/<game>`); per-game "Back up saves now" copies to `~/Library/Mobile Documents/iCloud~com~markoalagic~fable/saves/<bottle>/<game>/<timestamp>/` | iCloud container needs entitlement — falls back to `~/Documents/Fable Saves/` without Developer ID |
| **40** | Restore flow + scheduled auto-backups (daily/weekly setting). UI in GameSettingsView | |
| 40a | **Buffer.** Test with at least one save-heavy game; document patterns that don't match the locator's heuristics | |

### Bottle archiving

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **41** | `BottleArchive` (Day 21) reused for dehydrate/rehydrate. New `Bottle.status = .archived`; sidebar moves archived bottles to a collapsible group | Lifts off existing infrastructure — efficient slot |
| **42** | Auto-suggest archiving for bottles not launched in 30+ days (a notification, not automatic). Tests for dehydrate→rehydrate roundtrip | |

### Gamepad navigation

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **43** | GameController framework: capture connected controllers, build a `GamepadFocusEngine` that maps d-pad/A/B to NSResponder focus + key events | New territory; carve a focused day |
| **44** | Apply focus rings + d-pad nav to BottleListView and BottleDetailView; A button = primary action (Play / Create), B button = back | |
| 44a | **Buffer / model checkpoint.** This is a UX feature where a model swap is most disruptive — commit at end of each working session even if mid-feature | |

### Discord Rich Presence + shader cache + recents

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **45** | Discord RPC client (no SDK needed — it's a small JSON-over-named-pipe protocol). GameLauncher publishes on launch/exit. Settings toggle to opt out | Quick, satisfying win |
| **46** | Per-game shader cache management: discover cache locations for DXMT and D3DMetal, expose "Clear shader cache" + size in GameSettingsView | |
| 46a | **Buffer.** Recent / pinned / favorites in Library view (Day 30) — three-line code change with disproportionate UX value | |

### Tier 2 close-out

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **47** | **Release v0.4.0**. Stabilization + tag + notes + memory update | |

---

## Tier 3 — Diagnostics (Days 48–57)

### Backend A/B compare

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **48** | `BenchmarkRunner`: launches a game under backend A for N seconds, captures frametime log + ProcessMetrics samples, terminates, switches backend, repeats | Reuses Day 19 metrics + Day 17 per-game override |
| **49** | Chart view (Swift Charts) showing the two backends overlaid: frametime histogram + p50/p95/p99 + average CPU/mem. "Recommended: DXMT" verdict | |
| 49a | **Buffer.** Real-world test on at least one game; tune the metric to the user's actual experience | |

### Built-in micro-benchmark

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **50** | Source a tiny open-source D3D11 + D3D12 test scene (`dxvk-tests` has candidates). Bundle it into the app or download on first benchmark run | Sourcing the scene is the unknown |
| **51** | "Benchmark this bottle" action runs the scene with each available backend, writes a shareable score card (PNG + JSON) | Pairs with the compatibility DB later |

### Visual perf timeline + send-crash-report

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **52** | LogViewerView (Day 5 from earlier QoL) gains a "Timeline" tab parsing DXMT's frametime markers into a Swift Chart; click a spike to scroll the log to that timestamp | The data's already in logs — pure presentation lift |
| 52a | **Buffer.** GPTK frametime format differs from DXMT; handle both | |
| **53** | "Send Crash Report" action: bundles bottle.json + last log + `ps` snapshot at crash + Fable/Wine versions into a markdown-formatted GitHub issue draft; opens browser to pre-filled issue | Reuses Day 16 plumbing |

### Smart Bottle (log-pattern → suggestion engine)

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **54** | `LogPatternMatcher` with 30–50 seed rules: e.g. `MSVCP140.dll not found` → suggest vcredist; `unable to load d3d11.dll` → suggest enabling DXMT; `0xC0000005` in libGL → suggest GPTK backend | Carries the most ongoing value — every new pattern helps every user |
| **55** | Suggestion UI in LogViewerView ("3 suggestions found · Apply"); each suggestion has an explanation + one-click apply (install dep / enable backend / change setting) | |
| 55a | **Buffer.** Wire suggestions into the launch-failure toast: if a game exits non-zero, scan its log and surface a banner if Smart Bottle has anything to say | |

### Wine debug profile presets

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **56** | Debug preset picker in GameSettingsView: `Off / Graphics / Audio / Networking / All`. Each maps to a `WINEDEBUG=` env composition, log goes to a labeled file | Small but highly useful for users sending you reports |

### Tier 3 close-out

| Day | Scope | Why this slot |
|-----|-------|---------------|
| **57** | **Release v0.5.0**. Stabilization + tag + notes | |
| **58** | Retrospective + planning for Tier 4 (separate doc). Memory updates | |

---

## Flex protocol — for unforeseen difficulty + model swaps

### Built-in flex

Every `Na` lettered day is a **planned buffer slot**. Use it if the
named-day scope spilled; otherwise that day is invested in polish or
pulled forward into the next item. There are ~12 of these across the
38-day plan (~30% buffer ratio), which roughly matches the actual
overrun rate of the Day 11–20 sprint.

### Triggers that consume buffer

1. **Real-world dependency moves slower than planned** — IGDB API rate
   limits the auth flow, Heroic schema isn't what we expected,
   GameController framework has macOS 14 vs 15 quirks. Use 1 buffer day,
   then escalate to "park this item; pull next from queue".
2. **A test fails for non-obvious reasons** — sink at most 1 buffer day
   into the test; if not green, commit the failing test as `@Test
   .disabled("WIP — see issue #X")` and move on. Don't let one test
   eat the sprint.
3. **A real bug surfaces in something already shipped** — fix takes
   priority. The buffer day pays for it.

### Model swap protocol

The user flagged this explicitly: Fable 5 went restricted on 2026-06-12,
and the current session model could change again. The plan is built
to survive that.

**Hard rules:**

- **Commit at the end of every named day.** Even if the scope is
  half-done, commit a WIP marker. A fresh session model can resume
  from a commit but not from in-memory context.
- **Each day's commit message ends with a `Next:` line** stating the
  next concrete action ("Next: wire `BottleArchive.import(from:)` into
  BottleListView toolbar menu"). Future-you (or a future model) reads
  the latest commit and knows exactly where to start.
- **End-of-day note in `docs/sprint-log.md`** for non-trivial decisions:
  why we picked the schema we did, what was rejected, what's brittle.
  Spent context made durable.
- **At lettered (buffer) days, also update `MEMORY.md`** — the running
  context that any new session inherits. Keeps the model-swap blast
  radius small.

**Soft rules:**

- If the model swap is to a *more* capable model (Opus 4.7+, Fable 6
  becoming available again): pull a Tier 4 item forward as a stretch.
- If the swap is to a *less* capable model (Haiku-only fallback): drop
  scope on whatever's next, do a docs/test-coverage day instead. Some
  days actually benefit from a lighter model — Day 47 (release prep)
  and Day 57 (retrospective) are good candidates.
- **Never** assume the new model has the old session's context. The
  commit log + `docs/sprint-log.md` + `MEMORY.md` are the only state
  it inherits.

### Hard pause points

These are the safest "stop here for weeks if life intervenes" markers:

- **End of Day 26** — Tier 1 foundation (export/import + custom Wine)
  is complete; everything else builds on it.
- **End of Day 36** — Tier 1 closes with v0.3.0 shipped.
- **End of Day 47** — Tier 2 closes with v0.4.0 shipped.
- **End of Day 57** — Tier 3 closes with v0.5.0 shipped (= end of this
  plan; Tier 4 lives in `roadmap-tier-4-plus.md`).

Resuming from any of these takes ~10 minutes of context refresh.
Resuming from mid-item takes the rest of that day.

---

## Day count summary

| Phase | Named days | Buffer days | Total |
|-------|-----------|-------------|-------|
| Tier 1 — strategic | 14 | 4 | 18 |
| Tier 2 — major QoL | 9 | 4 | 13 |
| Tier 3 — diagnostics | 8 | 4 | 12 |
| **Total** | **31** | **12** | **43** working sessions |

Real-world calendar: at 4 sessions/week, ~11 weeks. At 2/week (more
realistic with day job), ~22 weeks ≈ 5 months. Adjust the day-to-day
mapping to match actual pace; the dependency order matters more than
the calendar.
