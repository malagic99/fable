# Changelog

## v0.22.0 — 2026-07-06

Legal-hygiene release: the donor bottle is now clean by construction.

- **Donor export.** Exporting a Steam bottle now asks: *Donor for a Friend*
  strips installed games (licensed content the recipient may not own),
  downloads, per-account data, and the owner's Steam login/session — the
  client itself travels and the friend signs in as themselves. *Full Backup*
  keeps everything, labeled for what it is. The exclusions feed both the
  archive and its checksum, so donor imports verify; the archived bottle.json
  drops the stripped game entries too.
- **LICENSE (MIT)** — the public repo finally has one — and
  **THIRD-PARTY-NOTICES.md** inventorying what Fable redistributes
  (innoextract + its dylibs), what it only downloads at runtime, and the
  D3DMetal never-bundle rule.

## v0.21.0 — 2026-07-06

The kit's scariest moment made boring, and the moat learns to grow itself.

- **Bottle export now scales to the real donor.** The prefix is tarred IN
  PLACE and the checksum streams through a pipe — a 56 GB Steam bottle no
  longer needs a staged copy plus a second full-size temp file (previously
  ~2× the bottle in scratch space and three full disk passes; now one
  streamed pass). The Export button shows live progress ("12.4 GB / ~56 GB")
  and a disk-space preflight refuses up front instead of failing at 90%.
- **Share This Setup on GitHub** (Game Settings): one click composes your
  working config — backend, cap, MetalFX, the hardware it ran on, tracked
  playtime — into a pre-filled `[Recipe]` GitHub issue. Same privacy contract
  as Send Feedback: nothing sent, you review and post. Issue templates ship
  in the repo; honest reports become built-in catalog entries.
- **Playtime survives quitting Fable mid-game** — open sessions fold into
  their totals on app termination instead of vanishing.
- ROADMAP.md rewritten to post-Friend-Kit reality: the 1.0 checklist, the
  1.x menu, the 2.0 money gate, and the honest non-goals with receipts.

## v0.20.0 — 2026-07-06

Fable learns the most expensive lesson we ever paid for — and CI makes sure
nothing forgets it.

- **The First Light rule, as behavior.** Every game exit now records (or
  clears) its crash signature per backend. When the *identical* int3-family
  crash shows up on two different backends, Diagnose Last Run leads with the
  honest verdict: it's the game's anti-tamper or a Rosetta CPU gate — no
  backend switch will fix it, stream it instead. Ends backend roulette; the
  verdict persists across relaunches and clears itself after a clean run.
- **Doctor names the culprit DLL.** `err:module:import_dll` lines are parsed
  and the missing DLLs named in the finding ("Wine couldn't resolve:
  XAPOFX1_5.dll, D3DX9_43.dll.") instead of sending you to read the log.
- **CI.** Every PR and push to main now builds and runs the full suite
  (397 tests) on GitHub Actions — including the localization gate and the
  data-catalog invariants. It caught its first real bug before it ever ran
  green: a Sendability hole in ArtworkStore's disk-cache load that the local
  toolchain tolerated.
- README refresh for the public repo: triggers, Doctor, hardware awareness,
  sharing formats, CI badge, contributor doc links.

## v0.19.0 — 2026-07-06

The Friend Kit — Fable's actual finish line — plus a knowledge-transfer sweep.

- **Bottle export/import is real.** The `.fbottle` archive layer (pack /
  verify / unpack, checksummed) existed but was wired to nothing. Now:
  bottle page → **Export** packs a shareable archive; Bottles → New Bottle
  tile → **Import Bottle (.fbottle)…** adopts one with a fresh identity and
  deduped name. Round-trip covered by tests, including double-import.
- **`scripts/friend-kit.sh`** assembles the whole kit: fresh app zip +
  friend README + any exported bottles/recipes staged in `kit-payload/`.
- **docs/FRIEND-README.md** — the one-pager a friend actually needs:
  the right-click→Open Gatekeeper ritual, Sikarugir/D3DMetal setup,
  importing the donor bottle, recipes.
- **Fable Doctor: 11 new signatures** from the June investigations —
  D3DMetal dlopen, dispatch-ABI mismatch (c0000142), quarantined dylibs,
  missing FreeType/GnuTLS, the Steam service WoW64 pipe, Metal command-buffer
  aborts, out-of-memory, Denuvo, XAudio, PhysX — each pinned to a real log line.
- **Committer hardening**: refuse sparse-preallocated downloads (logical
  size lies mid-download; allocated size can't) — closes a path where a
  paused download could be "committed" broken.
- **Recipes**: Ready or Not (Sikarugir + 120 fps + MetalFX), seeded from the
  real tested bottle (~4 h tracked).
- **docs/ARCHITECTURE.md**: the matched-pair thesis, the ABI law, the Steam
  CEF saga, and the dead-ends table — the repo now carries the systems
  knowledge, not just the code.

Known remainder: a cold-start onboarding dry-run on a fresh account is still
pending — do it before handing the first kit to a friend.

## v0.18.1 — 2026-07-06

Patch: the translations a Portuguese tester could still see through.

- **Enum labels localized** — trigger modes (Desligado / Resistência / Arma /
  Vibração), backend names (Integrado), Winetricks categories.
- **The String-ternary and interpolation traps closed**: `Text(flag ? "On" :
  "Off")` and `Text("…\(x)…")` silently skip localization; every occurrence
  (Tune sheet footers, trigger lab sliders, update banner, installer modes,
  counts) now routes through `L10n`.
- **New regression gate** fails the build on any future ternary/interpolation
  in `Text`/`.help`, with a short justified allowlist for verbatim data.
- Versioning rule written into `release.sh`: new capability = minor,
  everything else = patch (like this one).

## v0.18.0 — 2026-07-05

Tell Fable what broke — now that the repo is public.

- **Send Feedback** (Settings → About): bug, idea, or question, composed
  in-app and handed to the browser as a pre-filled GitHub issue. Anonymous
  to Fable by construction — the app sends nothing; the user reviews the
  exact text on github.com and posts it (or doesn't) themselves.
- **Opt-in system info.** A toggle appends the same three facts the About
  tab shows (Fable version, macOS version, hardware spec line) — previewed
  verbatim in the sheet before anything leaves the app. No serials, no
  usernames, no paths.
- The composer is a pure, tested model (`FeedbackReport`): category prefix
  in the title (labels don't survive the new-issue URL for non-maintainers),
  query-hostile characters (`+ & =`) percent-encoded, oversized messages
  trimmed to keep the URL browser-safe.
- Sheet localized in English, Spanish, and Portuguese.

Plus a UI-hierarchy polish pass now that Fable is in the wild:

- **The settings-tab wedge is gone.** Native TabView floated its tabs into
  the window titlebar — *above* the Gamer top bar that contains them. The
  five settings sections are now an in-content pill strip, the same pill
  the top bar uses (one shared `PillTabButton`).
- **Components had the same wedge** (its refresh lived in a toolbar, which
  conjured an empty titlebar band and pushed the nav down); the refresh now
  sits in the section header and the nav height matches every other screen.
- **Readable line lengths**: Settings and Components forms cap at 700 pt
  and center instead of stretching label–value rows across the window.
- Bottles wall gets a "Your bottles" heading, matching the games wall.
- Advanced → Folders buttons say "Open in Finder" once, not
  "Open Bottles Folder" next to a row already labeled Bottles.

And a full localization sweep (tester screenshots showed whole footers still
in English):

- **All 272 view literals now have es/pt entries** — settings footers, help
  tooltips, installer flows, Winetricks, onboarding, everything. Proper nouns
  ("D3DMetal", "120 fps") carry identical-value entries so the gate below
  stays exception-free.
- **Code-built strings localized**: bottle status badges (Pronta / Configurando
  / Precisa de reparo), "Backend override:", games count, DualSense On/Off,
  controller guidance, System/Light/Dark appearance names. The `String`-ternary
  trap (`Text(flag ? "On" : "Off")` silently skips localization) is documented
  and fixed everywhere it occurred.
- **The gate**: `LocalizationCoverageTests` scans the real source tree —
  every view literal must exist in es and pt, every `L10n.string` key in all
  three languages — and fails naming the exact strings you forgot.
- **The template**: `docs/LOCALIZATION.md` — how strings resolve, the
  30-second recipe for adding one, how to add a whole language.

## v0.17.0 — 2026-07-05

Fable knows your Mac.

- **Hardware detection** (`HardwareProfile`): chip, unified memory, P/E core
  split, GPU core count, and model identifier — read once at startup from
  sysctl + the GPU registry. Shown in Settings → About → **This Mac**.
- **Hardware-aware performance defaults.** Recommendations now consult the
  actual machine: a Max/Ultra with 48 GB+ starts at a 120 fps cap with MetalFX
  off (real headroom); Pro-class or 24 GB machines get the steady 60 + MetalFX
  (unified memory is shared with the GPU); chip tier alone isn't headroom — a
  32 GB Max still shares. Applied by the same only-if-untuned rule as before.
- **The Performance section says why.** A one-line, machine-specific
  explanation ("On your Apple M4 Pro with 24 GB of unified memory, …") sits
  above the backend footer — localized in English, Spanish, and Portuguese.

## v0.16.0 — 2026-07-05

Fable habla español — e agora fala português.

- **In-app language switch** (Settings → Appearance → Language): System /
  English / Español / Português, with a one-click relaunch to apply.
- **Spanish revived.** The UI-review rewrites had quietly regressed es
  coverage; the wall, Gamer top bar, inspector, Settings, bottle page, and
  common sheets are translated again — verified live on screen.
- **Portuguese added** (for a tester) — same coverage as Spanish.
- A parity test now locks every code-resolved key into all three languages,
  so a missing translation fails the build instead of rendering a raw key.
- Honest scope note: long-form footers and hover help remain English for now.

## v0.15.3 — 2026-07-04

Supervisor review, item 3: tests where the bugs actually were.

- **Wall grouping extracted to pure logic** (`LibraryGrouping.sections`) and
  covered: platform/health/bottle slicing, empty-section dropping, natives
  always getting their own section under health/bottle.
- **ArtworkStore cache semantics tested** — including the exact regression
  that shipped (custom cover saved to disk but never read back on a cold
  start), custom-art-wins, offline behavior, and late disk drops. All tests
  run fully offline.

## v0.15.2 — 2026-07-04

Supervisor review, items A1–A3 + quick wins: the dedup sweep.

- **One CoverCard.** The wine and native wall tiles were ~80% copy-paste; now
  one shared `CoverCard` carries the cover, health dot, Playing chip,
  selection ring, and hover — the two wrappers only decide what to feed it.
- **One running rule.** The Fable-launched-OR-detected check lived in five
  call sites; now `GameLauncher.isRunning(_:in:activity:)` is the single path.
- **One confidence entry point.** `GameConfidence.assess(game:recipes:quirks:)`
  replaces three inline copies of the recipe+quirk lookup.
- **FilePicker grew up:** image/file-by-extension/folder/applications pickers
  replace seven hand-rolled NSOpenPanel blocks (and retire the deprecated
  `allowedFileTypes` API in the process).
- **No more retroactive `URL: Identifiable`** — sheet items use a small
  wrapper instead of a module-wide conformance.
- The Classic sidebar section is now called **Games** (it shows the wall, not
  the old "Library").

## v0.15.1 — 2026-07-03

Supervisor review, item 1: the release ritual is now a script.

- `scripts/release.sh prepare <version>` — bumps version + build, verifies the
  CHANGELOG section exists, runs the test suite.
- `scripts/release.sh publish <version> <title>` — on a clean main only: tags,
  pushes, rebuilds, zips, and creates the GitHub release with notes pulled
  straight from the CHANGELOG section. Refuses dirty trees, wrong versions,
  and unaligned HEADs — the guardrails the hand-rolled ritual didn't have.

## v0.15.0 — 2026-07-03

The library learns your history — and two long-standing wrongs put right.

- **Playtime + last played.** Fable-launched sessions accumulate real playtime
  (launch → exit); the inspector shows "Playtime" and "Last played". Native
  launches hand off to the platform, so they honestly track only the moment
  ("last played"), never a guessed duration.
- **Per-game notes.** A freeform notes field in the Tune sheet — mod setup,
  launch quirks, where you left off. Shown in the inspector when present.
- **Group the wall.** Wall options (⋯) → Group By: Platform (Windows vs native
  Mac), Health (verified / tweaks / won't run / untested), or Bottle — which
  doubles as the account view when two Steam accounts live in separate bottles.
- **Fetch Missing Covers** (also under ⋯) retries the artwork pipeline for
  every game without a cover, clearing this session's "no art" marks first.
- **Fixed: custom covers for the Steam tile no longer vanish on relaunch.**
  The Steam client skips art *fetching*, but the skip also skipped reading the
  saved custom cover back from disk — set once, gone next launch. Custom
  covers now persist for every title, including ones with nothing to fetch.
- **Fixed: a game launched from inside Steam now shows as running** (not just
  Steam). Steam-spawned processes carry Windows-style paths with no bottle
  path in them, so the old unix-path match never saw them; detection now also
  matches the game's drive_c-derived Windows path.

## v0.14.3 — 2026-07-03

Visual harmonization. (UI review, final pass.)

- **Design tokens, applied:** two corner radii (12 container / 8 inner) and
  three semantic surface tones replace the ad-hoc values scattered per view.
- **One backend label source:** the "Built-in" / DXMT / GPTK / … label lives in
  one place; `.off` is now honestly "Built-in" instead of "Wine" (everything
  here is Wine — .off means Wine's built-in D3D path).
- **The dot scale tells one truth:** health dots are green/orange/red/gray
  only. Native Mac games show an  glyph by their name instead of hijacking
  the health scale with blue.
- **Legend moved behind "?"** next to search — learn-once info no longer
  occupies a permanent row.
- **Hero Play shows only when unambiguous** (bottle has exactly one game).
- Top bar typography is semantic (scales with the system), the Gamer face no
  longer double-titles the window, and the longest footers were cut to one
  sentence (mechanism lives in hover help).

## v0.14.2 — 2026-07-03

Tune tunes what the inspector shows. (UI review, priority 3.)

- **The Tune sheet gained a Performance section** — Frame Rate Cap and MetalFX,
  the two facts the inspector displays but previously offered no way to change
  from there (they were three levels deep behind Advanced Mode). Honestly
  labeled: these are shared by every game in the bottle.
- **Trigger sheet titles unified** ("DualSense Triggers — <name>" everywhere).
- **The bottle page's trigger row no longer changes meaning with state:**
  "DualSense Triggers" + On/Off value + a constant "Configure…" verb, instead
  of a button whose label flipped between status and action.

## v0.14.1 — 2026-07-03

Settings regrouped by intent. (UI review, priority 2.)

- **Five tabs that mean something:** Appearance (interface + themes), Library
  (compatibility + artwork), **Defaults** (everything a new bottle starts
  with — Windows version, DXMT, frame cap, log level, finally in ONE place),
  Advanced (shader cache, folders, onboarding reset), About.
- The old General tab (a seven-section junk drawer) and the Performance tab
  (two controls that were also new-bottle defaults) are gone.
- **About no longer duplicates Components:** runtime versions live in one
  place; About points there.
- Housekeeping: stray screenshots untracked from the repo root (now
  gitignored).

## v0.14.0 — 2026-07-03

One library. (UI review, priority 1.)

- **The game wall is now THE library — in both faces.** The Classic interface's
  Library section shows the same wall as the Gamer face: covers, confidence
  dots, native macOS games, the inspector, custom covers. The old second
  library grid (wine-only, different cards, no natives) is gone.
- **One unified Add flow.** The wall's Add tile now carries every way a game
  enters the library: native Steam import, **Heroic (Epic/GOG) import** (was
  stranded in the old Library), a plain Mac app, and "Set Up in a Bottle…" for
  Windows games.

## v0.13.6 — 2026-07-03

Lane 1 verification sweep (roadmap) + one fix that fell out of it.

- **Fix: stale native-Steam manifests are no longer offered for import.** A
  Steam `appmanifest_*.acf` can claim a game is installed (with a large
  SizeOnDisk) while its `common/<installdir>` folder is an empty husk — Steam
  then fails the launch silently. Observed live: Balatro's manifest said 85 MB,
  the folder held one `.DS_Store`. The import list now checks the files
  actually exist on disk (size-capped walk, early-out at 5 MB — a real install
  costs a handful of stat calls).
- **Verified: shader-cache restore.** Simulated a macOS purge of a live wine
  Metal cache; Fable's startup restore detected it and healed it byte-identical
  from the snapshot. Cache paths are keyed by GPU + driver build, not the boot
  session, so a plain reboot shouldn't invalidate them. (The final word — no
  first-run stutter after a real reboot — still needs a play session.)
- **Verified: the D3DMetal onboarding step, live.** First time seen outside
  tests: correctly detects the installed D3DMetal and shows the ready state.
  (Cosmetic: version renders as "10.0_4" — underscore from the raw string.)
- **Verified: `steam://rungameid` cold-start handoff.** From a fully cold
  native Steam: client starts, auto-logs-in, and processes the launch in ~30 s.
- **Closed: Z: drive self-heal watch.** No recurrence in any log since the heal
  shipped; the bottle's `z:` symlink is healthy.

## v0.13.5 — 2026-07-03

Trigger resistance now survives *any* app being frontmost — raw HID.

- **Root cause found:** macOS's GameController framework silently drops trigger
  *output* writes whenever Fable isn't the frontmost app. v0.13.3's keep-alive
  was firing every second, but the writes went nowhere until Fable was clicked
  back into focus (which is exactly the "turns back on when I click Fable"
  symptom).
- **Fix: Fable now writes trigger effects straight to the DualSense over raw
  HID** (IOHIDManager) — the same path Steam Input and SDL use — which has no
  focus gate. USB report `0x02` and CRC-sealed Bluetooth report `0x31`, with
  the community-standard effect encoding (feedback/weapon/vibration). Only the
  trigger flags are ever set, so the game's rumble and lightbar are never
  touched. GameController remains the fallback writer and still provides pad
  detection and the live pull readout in the Trigger Lab.
- Together with the keep-alive: the profile is re-asserted once a second over a
  channel that works in the background, so resistance holds while the game is
  frontmost.

## v0.13.4 — 2026-07-03

- **Trigger editor layout fixed properly.** v0.13.1's attempt (a scroll view
  plus a `minWidth/idealWidth` frame) backfired: the long descriptive caption
  has a huge single-line intrinsic width, so a non-fixed width let the content
  overflow both edges — clipping the header text ("Triggers" → "riggers") — and
  the `minHeight` forced a tall sheet with a dead void under the panels. Now the
  sheet is a **fixed 640 wide with a natural, content-sized height**: the
  caption wraps, nothing clips, the two L2/R2 panels get comfortable room, and
  the sheet is exactly as tall as the current mode needs (no empty space).

## v0.13.3 — 2026-07-03

Adaptive triggers survive the game taking focus.

- **Resistance no longer dies when the game grabs the controller.** Two causes,
  both fixed:
  - Fable now opts into `GCController.shouldMonitorBackgroundEvents`, so it can
    keep writing to the DualSense while the game window is frontmost and Fable
    is in the background (previously the system stopped delivering our writes
    the instant the game took focus).
  - A **keep-alive** re-asserts the active profile once a second while a
    profiled game is running, so if the game (or Steam Input) clears the
    triggers on launch/focus, the resistance is restored within a second and
    stays stacked — instead of Fable's "unchanged" cache leaving it dead.
- Config-sheet previews pause the keep-alive so they don't fight the effect
  you're auditioning.

Note: if a game is driving the pad through **Steam Input**, Steam may own the
triggers outright — turn Steam Input off for that controller so Fable's
resistance can hold.

## v0.13.2 — 2026-07-03

Themes now reach the classic views.

- **Grouped forms let the window wash through** — Settings, bottle details,
  game tuning, Components, and the create/install sheets used to paint their
  own opaque grouped-form panel *over* the theme background, which flattened
  a themed wash (most visibly Pitch Black — the OLED black was covered by a
  lighter panel). When a theme paints a window wash (Midnight, OG Steam, Pitch
  Black) or a custom background is set, those forms now drop their backing so
  the wash shows through. The default (untinted) look is unchanged.

## v0.13.1 — 2026-07-02

Late-night polish.

- **Pitch Black theme** — a new built-in for late-night sessions: the window
  wash is near-opaque `#000000`, so on an OLED/HDR panel the background pixels
  switch fully off (true black, no backlight glow, easier on the eyes and the
  battery). Calm blue accent, dim brand gradient to keep light emission low.
  (Not an HDR *pipeline* — there's no honest lever for that — but on HDR/OLED
  hardware pure black is genuinely black.)
- **DualSense trigger editor no longer overflows** — the Trigger Lab is now
  scrollable and the sheet is larger, so the two L2/R2 panels (up to three
  sliders each in Weapon/Vibration mode) always fit instead of being clipped
  off the bottom of the screen.

## v0.13.0 — 2026-07-02

One wall for everything: native macOS games join the library.

### Native games

- **Import from native Steam** — Fable reads the macOS Steam client's install
  manifests and imports your native games (Steam's own tooling — redists,
  SteamVR, controller configs — is filtered out). They launch through the
  native client (`steam://`), so login, DRM, and cloud saves stay Steam's.
- **Add any Mac app** — App Store, web, anywhere: pick a `.app` and it joins
  the wall, launched natively. Live "Playing" chip for .app games.
- Native covers use the same art pipeline (Steam natives fetch by appid —
  no search needed) and support custom covers. A blue **native** dot marks
  them: no Wine, no bottle, no tuning — it just runs.
- The wall's **Add game** tile offers all three paths: native Steam import,
  Mac app, or Bottles for Windows games.

## v0.12.0 — 2026-07-02

Make it yours: themes, appearance, backgrounds, and custom covers.

### Themes (Settings → Themes)

- **Three built-ins**: Fable (the stock purple→indigo), **Midnight** (deep-night
  blues on near-black), and **OG Steam** — the 2004 olive-and-gold skin,
  lovingly approximated. A theme recolors the accent, the identity gradient,
  and lays a window wash behind everything.
- **Themes are files.** Export the current theme as a `.fableskin` (its
  background image travels embedded) and import ones from anywhere — a tiny
  theme plug-in system. Imports can't shadow the built-ins.
- **Appearance**: System / Light / Dark, independent of theme (a theme suggests
  one when applied; you can override).
- **Custom background**: pick any image to sit behind the whole window (most
  visible in the Gamer interface); it overrides the theme's own background.

### Custom covers

- Right-click any cover (Gamer wall or Library): **Set Custom Cover…** uses
  your own image (persists, wins over fetched art), **Refresh Cover** re-runs
  the pipeline when the fetched art is wrong.

## v0.11.0 — 2026-07-02

Real box art everywhere, and the Gamer interface goes Big Picture.

### Cover art pipeline

- **Tiles show real box art now.** Covers resolve in order: the game's Steam
  app ID from its bottle (official CDN portrait, keyless) → a keyless Steam
  store search by name (so Epic/GOG/Heroic copies of Steam titles get art too)
  → SteamGridDB when you add a free API key (Settings → Artwork) → the game's
  own exe icon as the offline fallback.
- Cached on disk after one fetch per title; a name match is required before
  art is accepted (wrong art is worse than no art); the Steam client itself is
  excluded. One toggle turns the whole pipeline off for a fully offline app.
- **Legible at any size**: on the wide Bottle/Library cards the art fills the
  tile behind a bottom-heavy dark scrim, with text switched to white — names,
  facts, and badges stay readable over any artwork.

### Gamer interface — Big Picture layout

- Navigation moved to a **horizontal bar across the top** (identity left,
  sections beside it, now-playing chip right) — no sidebar at all; content
  runs full-bleed underneath. Steam Big Picture's shape in Fable's language.

### Consistency

- The **tile-size slider is now the same control in the same place** on all
  three grids — inline above the Bottles grid, the Library grid, and the Gamer
  cover wall (it lived in the window toolbar on Bottles and was missing from
  Library entirely; Library tiles now actually resize too).

## v0.10.1 — 2026-07-02

Gamer-interface polish and always-on triggers.

### Gamer interface

- **One navigation.** The rail now hosts Play plus Bottles, Components, and
  Settings directly — the nested Classic sidebar is gone, so there's no longer
  a menu inside a menu.
- **Resizable tiles.** A slider (in the Play header and the Bottles toolbar)
  grows the covers and cards from laptop-tight to couch-distance — hook the
  laptop to a TV and size them to taste. Persisted.
- **Add a bottle, your way.** The toolbar "+" is gone; the dashed New Bottle
  tile is now the single entry point and offers a choice — plain bottle or
  Steam bottle.
- **Inspector.** Play and Tune sit together at the top (Tune was buried at the
  bottom).

### DualSense triggers, always on

- Trigger resistance is now a hardware layer Fable maintains that **stacks on
  top of the game's own input** — so a game with zero native trigger support
  still gets resistive triggers. Whenever a game runs in a bottle (including one
  launched from inside Steam), the bottle's trigger profile is applied and held;
  it clears only when the bottle goes idle. Global-per-bottle by design.

## v0.10.0 — 2026-07-02

Two faces, your pick: the new **Gamer** interface joins Classic, chosen on
first launch and switchable any time.

### The Gamer interface — games first

- **Cover wall**: every game across every bottle as covers. Single-click to
  inspect, double-click to play. Search built in.
- **Confidence dots** on every cover — will it run, before you click:
  green = a verified recipe matches, amber = known caveats, red = anti-cheat
  won't run under Wine, gray = honestly untested. Powered by the recipe
  catalogs + the quirk system's anti-cheat database.
- **Inspector**: how the selected game runs — health, backend, frame cap,
  MetalFX, and its adaptive-trigger L2/R2 profile — with Play and Tune right
  there. You play and tune without ever thinking about bottles.
- **Workshop**: the complete Classic app, one rail-click away. Nothing was
  removed — bottles, components, settings, and all tools live there.
- **Now playing** appears in the rail while a game runs.

### Choosing

- New **onboarding step**: pick Classic or Gamer as your default on first
  launch, with sketch previews of each.
- **Settings → Interface → Style** switches live, any time, both directions.
- Existing setups keep Classic — nothing changes until you choose.

## v0.9.0 — 2026-07-02

UI redesign: fluid, clean, balanced. Reviewed live on screen, then rebuilt
around one design language (`FableTheme`).

### The bottle page is games-first now

- **Hero header**: cover art, the bottle's name in large type, status +
  backend chips, quick facts (Windows · games · size), and a prominent Play —
  the one thing you actually do with a bottle. The wall of metadata that used
  to sit above your games moved to a "Details" section at the bottom
  (advanced mode).
- The settings column is width-capped and centered so it no longer floats in
  a void on large windows.

### One card language

- Bottle and Library tiles share one roomier card: bigger cover art, clearer
  title, dot-separated quick facts, springier hover lift with a subtle glow.
- **Backend badges stopped shouting.** Sikarugir was alarm-pink on every card —
  red tones now mean actual problems; backends get quiet informative tints
  (Sikarugir is indigo, matching the app's identity).
- A dashed **New Bottle** tile joins the grid, so a sparse library reads as an
  invitation instead of a void.

### Identity

- The wineglass-on-gradient mark (previously onboarding-only) now heads the
  sidebar — the app carries its own identity.
- `FableTheme` centralizes the gradient, card surface, and backend tints;
  one shared `ExeIconView` replaced three copy-pasted icon loaders.

## v0.8.1 — 2026-07-02

Backend surgery: one launch flow, a tested routing core, two trigger fixes.
No user-facing behavior changes beyond the fixes.

### Under the hood

- **One launch flow.** The Play/Stop logic that was copy-pasted across three
  controls (Library, grid quick-launch, game rows) now lives in one place —
  `GameLauncher.launchSmart`/`stopSmart`, with the launcher's collaborators
  wired once at startup. The Steam-prerequisite nudge now fires consistently
  from every Play control (it was Library-only), and it no longer false-fires
  in the window right after Fable itself started Steam.
- **The launch-routing core is now tested.** Backend → wine binary / runtime
  key / wineserver-drain, plus the environment layering (base → backend →
  performance → per-game wins) were the most load-bearing untested lines in the
  app. `composeLaunchPlan` gained a runtime-resolution seam and 10 tests lock
  the whole table.

### Fixes

- **Closing the trigger config sheet no longer kills a running game's trigger
  profile** — the config panel previews without disturbing the session-applied
  profile, and restores it on close.
- **Honest label on per-game trigger overrides**: they apply when a game is
  launched from Fable; a game started from inside Steam keeps the bottle
  default (that's a Wine-boundary constraint, now stated in the UI instead of
  silently surprising you).

## v0.8.0 — 2026-07-01

Two controller/setup features.

### DualSense adaptive triggers

- Set a **static adaptive-trigger feel per bottle** — a resistance wall
  (weapon), constant tension (feedback), or a buzz (vibration) on L2/R2 — with a
  **per-game override**. Presets (Shooter, Racing, Heavy) get you started, and
  the config panel **previews live** on the pad as you drag a slider. Applied
  when a game launches, cleared when it exits. Validated on hardware over USB and
  Bluetooth.
- Honest scope: these are static profiles you set (like Steam Input's trigger
  config) — a Wine game's *own* contextual trigger effects can't cross the Wine
  boundary.

### D3DMetal set-up in the first-run wizard

- New **mandatory graphics step** in onboarding: detects Apple's D3DMetal (via
  the free Sikarugir), shows its version, and offers **one-click set-up** — or
  guides installing Sikarugir when it's missing. Makes the flagship backend
  (Steam + D3D12) work out of the box for a new user, with an informed "continue
  without it" escape for those who only want older D3D9 games.
- **Sikarugir updates** are now detected and applied (it was install-once);
  a newer engine on disk shows an "Update" action.

## v0.7.1 — 2026-07-01

Accurate Play/Stop state — Fable now knows what's *actually* running.

### Fixes

- **Real running detection.** Fable used to only know about games it launched
  itself, so state was wrong in two common cases. It now scans the process table:
  - A game launched **from inside Steam** shows as running.
  - A process that **lingers after its window closes** is reflected correctly —
    no more stale "running" that never clears (and no more Steam appearing idle
    while a game runs, or vice-versa).
- **Stop actually stops it.** For a game Fable didn't launch (or a lingering
  one), Stop now falls back to killing the bottle's wine tree instead of doing
  nothing.
- **Steam prerequisite nudge.** Launching a Steam game (under
  `steamapps/common`) while the Steam client isn't running now shows a clear
  "start Steam first, then launch it from your Steam library" message instead of
  a cryptic failure.

## v0.7.0 — 2026-06-29

Shader cache management. (Version is just "where we stand" — the publication/
distribution track is parked; Fable is a polished personal tool.)

### New — durable, offloadable shader cache

- **Shaders survive a reboot now.** D3DMetal compiles its Metal pipelines during
  play — the reason a game smooths out after its first hour — but those live in
  macOS's volatile darwin cache, which a reboot/cleanup purges (bringing the
  first-run stutter back). Fable now keeps a durable copy and **restores it
  automatically at startup** when the live cache was purged.
- **Offload to external storage.** Settings → Shader Cache shows the saved size
  and lets you back the cache up to an external drive to reclaim local space,
  then bring it back on demand.
- Automatic snapshot after each session + auto-restore at startup; manual
  back-up / bring-back in Settings.

### Honest scope

- Metal compiles shaders on-demand during play — there's **no pre-build**
  (no Fossilize/Steam-precache equivalent), so the cache fills as you play and
  pays off from the second run on.
- Unlike Proton's portable per-game `.dxvk-cache`, the D3DMetal cache is Apple's
  per-app Metal cache; Fable manages it per-machine for the backend, never
  touching Apple/system or the shared global Metal cache.

## v0.6.1 — 2026-06-27

Bug-fix pass from real-world testing (Ready or Not running flawlessly — fans
near-silent and temps barely above room after the first hour).

### Fixes

- **A failed winetricks verb no longer destroys the bottle.** Bottle creation
  used to abort *and self-delete* if any verb failed — so a `corefonts` download
  hitting a dead SourceForge mirror nuked the whole bottle on every retry. Verbs
  are now best-effort: a failure is recorded and surfaced ("retry from the
  bottle's Winetricks button"), and the bottle is still created.
- **Wine drive self-heal.** Fable now ensures the standard `C:` → `drive_c` and
  `Z:` → `/` mappings exist before every launch (and on prefix creation). Fixes
  the "Wine keeps looking for the Z: drive it can't find" failure when running an
  exe or installer located anywhere outside `C:`.

### New

- **"Winetricks…" button** in a bottle's Wine Tools, next to Wine Settings —
  browse/install runtimes, fonts, and components, and retry anything that didn't
  finish during setup.

## v0.6.0 — 2026-06-27

The big one. Free Steam doesn't just render now — it **installs and plays AAA
games end to end**, your whole library lives in one place, the app picks the
right backend and holds a steady frame rate on its own, and it tells you what's
wrong when something breaks. This release rolls up the "bulletproof installs"
(v0.5) and "your whole library" (v0.6) milestones.

### Headline — free Steam that installs *and* plays AAA games

- **Steam installs end to end.** `WINEMSYNC=1` kills the IOCP syscall spin that
  throttled big downloads to ~0 Mbps; `SteamInstallCommitter` finishes installs
  stalled on the dead-WoW64 commit step (auto-heals on bottle open and on Steam
  exit); and Fable now auto-runs the VC++/DirectX redistributables Steam unpacks
  into `_CommonRedist` but never executes — no more missing-`vcruntime140.dll`
  crashes on first launch.
- **DEATHLOOP (30 GB D3D12 AAA) runs stable**, validating the whole chain.

### Library + import

- **Library view** — every game across every bottle in one searchable grid,
  one click to play, cover art from the game's own icon.
- **Import from Heroic** — pulls installed Epic / GOG / Amazon games into a
  bottle (symlinked, no copy), filtering out uninstalled, mac-native, and
  redistributable entries.

### Smart Bottle gets smarter

- **Auto backend pick** — an untouched bottle picks the right backend the first
  time you press Play (validated recipe, or modern-D3D compatibility markers).
- **Quirk system** — preemptive per-game verdicts in the compatibility banner:
  the offline **anti-cheat database** (Apex/Valorant/etc. flag "won't run on
  Wine" by name, pre-install) and **ProtonDB** community ratings (opt-in,
  cached, off by default — it sends a Steam app ID to a third party).
- **Shareable recipes** — export a tuned game as a `.fablerecipe`; import one
  and it overrides the built-in catalog so the setup auto-applies.

### Stability + diagnostics

- **The "rubber mat"** — games launch at high QoS (performance cores), Fable
  gets out of the way during play (no `ps` sampling while you're in-game, no
  disk walks mid-session), a one-click **Rock Solid** preset (60 fps cap +
  MetalFX), and a thermal nudge when the Mac starts throttling.
- **Fable Doctor** — "Diagnose Last Run…" reads a game's Wine log and explains
  what went wrong (missing runtime, anti-cheat, backend mismatch) in plain
  language.
- **Controller support** (PlayStation DualSense / DualShock 4) and runaway-log
  protection (the msync flood that wrote 25 GB logs is silenced; a pruner caps
  the rest).

### Under the hood

- **Agent-maintainable core** — the scattered Wine env fixes and Steam paths are
  centralized in `WineEnv` / `SteamPaths`, every quirk mapped in
  `docs/wine-quirks.md` with its rationale and how to change it.
- ~280 tests across ~68 suites, all passing.

### Known limitations

- Distribution is still the gate to 1.0: builds aren't yet notarized/signed
  (needs an Apple Developer ID), so first launch needs right-click → Open.
- HDR output isn't exposed — a running Wine game's Metal layer is owned by
  D3DMetal in the subprocess, with no Fable-side lever to force it.
- Kernel anti-cheat games (EAC/BattlEye/Vanguard) can't run under any macOS
  Wine; the quirk system now flags them up front instead of letting you find
  out the hard way.

## v0.4.1 — 2026-06-15

Compatibility release. Headline is a free fix that unblocks a whole
class of games, plus the Sikarugir D3D12 backend and the DXVK/vkd3d
correction.

### Headline — the AVX free fix

- **`ROSETTA_ADVERTISE_AVX=1` is now set on every launch.** Default
  Rosetta 2 advertises only SSE4.2 to translated x86 games (AVX=0,
  AVX2=0, FMA=0, BMI2=0). Many 2020+ titles run a CPU-feature check at
  startup and deliberately abort (int3) if AVX/AVX2 is missing — an
  invisible failure that looks like a graphics/Wine bug but is the CPU
  gate. This single env var flips AVX/AVX2/FMA/BMI2 on (verified on
  macOS 26.5 / M4 Pro). CrossOver and GPTK do this internally; Fable now
  matches them, for free, across every backend. No-op on native-arm64
  Wine.

### New backend

- **Sikarugir backend** — discovers a local Sikarugir install, extracts
  its GPL wine-10.0 engine into Fable's components, and overlays the
  d3dmetal renderer (D3DMetal recompiled against modern Wine). This is
  the free matched-pair recipe — modern SEH + real D3D12→Metal — that
  Apple's wine-7.7 GPTK can't provide. Architecture verified identical
  to CrossOver 26.2's commercial implementation.

### Fixes

- **DXVK backend now installs vkd3d-proton for D3D12.** DXVK only does
  D3D9/10/11; D3D12→Vulkan is the separate vkd3d-proton project. The
  backend's DLL routing now includes `d3d12core` (vkd3d 3.x split it
  out) and the display name names vkd3d explicitly.

### Notes

- 174 tests across 47 suites, all passing.
- Known limitation surfaced this cycle: games with packed/protected
  exes whose anti-tamper rejects the emulated environment (e.g. certain
  cracked repacks) abort identically on every backend including
  CrossOver — no wrapper fixes those; use a clean release or stream from
  a Windows PC. Smart Bottle's heuristics flag the telltale signs.

## v0.4.0 — 2026-06-14

Pushed past the Wine 7.7 ceiling. New backends, Smart Bottle
compatibility scanner, and the Info.plist version finally matches the
binary (v0.1.0 had been shown in Settings since the initial sprint).

### Headline

- **Two new graphics backends** that bypass GPTK's wine-7.7 SEH wall:
  - `dxvk` — D3D11/12 → Vulkan → MoltenVK → Metal on Wine Devel
    11.10. Loses D3DMetal's optimization but supports modern Wine
    SEH that GPTK fails on (the 007 First Light int3 wall).
  - `crossover` — routes through the user's installed CrossOver.
    Modern wine + Apple-licensed D3DMetal in one stack. Auto-detected
    at `/Applications/CrossOver.app`.
- **Smart Bottle** — `CompatibilityScanner` walks game install dirs
  and flags Streamline, DirectStorage, EAC/BattlEye/Vanguard, Goldberg
  with missing `steam_interfaces.txt`, repack tokens, Denuvo. Inline
  expandable banner under each game with severity + suggestion, plus
  a "💡 Try DXVK" / "Try CrossOver" recommendation chip when a better
  backend is detected.
- **First-launch wizard** (Day 21, was Stage B1 — pulled forward).
  Welcome → Source (Steam / Heroic-GOG-Epic / Manual) → First bottle
  from a template → Done. Re-runnable from Settings.

### Backends & runtime

- `GraphicsBackend` enum gains `.dxvk` and `.crossover` cases with
  backward-compat JSON decoding for v0.3.0 bottles.
- `GameLauncher.launch()` routes each new backend with its own wine
  binary + env; runtimeKey separates them in the multi-runtime
  conflict check.
- `CrossOverManager` discovers CrossOver across 23/24/25 path layouts.
- `DXVKManager` provides launch env (`WINEDLLOVERRIDES=…=n`,
  `DXVK_FRAME_RATE`, `DXVK_LOG_PATH`) and a prefix-presence check.
- `CompatibilityRuntime.discover()` order: CrossOver → WhiskyWine →
  Heroic GPTK → Fable's GPTK. Reversed from v0.2.0 because CrossOver
  has the WoW64 stack patches the others lack.
- `GPTKManager.overlayEvaluationLibraries` now strips
  `com.apple.quarantine` after merging the dmg payload. Without this
  Wine running under Rosetta failed `dlopen("D3DMetal")` with
  `STATUS_DLL_INIT_FAILED`.

### Onboarding & UX

- First-launch wizard surface (`OnboardingState` + `OnboardingView`).
- SwiftUI's `Text`/`Label`/`Button` localization now actually works —
  `make-app.sh` mirrors `.lproj` resources into `Fable.app/Contents/
  Resources` and stamps `CFBundleLocalizations`. v0.3.0 ad-hoc builds
  showed raw keys like `sidebar.bottles`.

### Tests

159 tests across 44 suites, all passing.

### Known limitations

- DXVK still has to be installed once per bottle via `winetricks dxvk`
  — automation slated for a v0.4.x patch.
- CrossOver detection assumes default `/Applications/CrossOver.app`
  install path; non-standard locations aren't supported yet.
- 007 First Light still doesn't run because of platform-level
  Streamline + Goldberg limitations — not a Fable bug, but Smart
  Bottle now surfaces the cause pre-launch.

## v0.3.0 — 2026-06-13

First-launch experience + foundations for bottle export/import +
critical localization fix. Test build cut off `dev` HEAD so users can
exercise the new wizard + Steam install flow in the real world.

### Headline

- **First-launch wizard.** Four-step flow on first open: Welcome →
  Where are your games? (Steam / Heroic-GOG-Epic / Manual) → Create
  your first bottle (pre-fills the template based on your source) →
  You're all set. Localized in English + Spanish; re-runnable from
  Settings → About.
- **CrossOver wins for 32-bit installers** by default now. The
  `CompatibilityRuntime.discover()` order was backwards in v0.2.0 —
  preferred Fable's bundled GPTK (wine 7.7 base, no WoW64 patches)
  over CrossOver (which has years of macOS-specific patches). Reordered:
  CrossOver → WhiskyWine → Heroic GPTK → Fable GPTK. Substantially
  improves the success rate on ISDone/FreeArc-packed installers.
- **Localization actually works now.** SwiftUI's `Text("foo")` /
  `Label("foo", systemImage:)` / `Button("foo", action:)` auto-resolve
  via `Bundle.main`, but v0.2.0 only put the .strings files in the
  SwiftPM resource bundle — every key rendered raw (you'd see
  "sidebar.bottles" instead of "Bottles"). `make-app.sh` now mirrors
  `.lproj` dirs into the app's main Resources and stamps
  CFBundleLocalizations. Affects every translated string in the app.

### Foundations

- **`BottleArchive` utility** — packs a bottle + prefix + manifest
  into a tar+zstd `.fbottle` archive; `inspect()` reads just the
  manifest; `unpack()` validates schema version and prefix SHA-256.
  No UI yet — that lands in v0.3.1 (export button) and v0.3.2
  (drop-to-import). Use case: install in CrossOver where WoW64 works,
  export, import into Fable for everyday play.
- **Roadmap docs** — `docs/roadmap-tier-1-3.md` (Days 21–58 day-by-day,
  three planned releases v0.3 → v0.5) and `docs/roadmap-tier-4-plus.md`
  (gate-driven stages A–F up to v1.0.0). Both include a model-swap
  protocol so session changes don't lose context.

### Bug fixes

- Onboarding **Done step never showed** — `advance()` to `.done`
  flipped `hasCompleted`, which dismissed the sheet before the user
  saw "You're all set". Now only the Start Playing button completes
  the flow.
- Runtime-built `LocalizedStringKey("foo.\(x)")` strings rendered raw
  (only literal-built keys auto-resolved). Routed through `L10n.string()`
  for the source-picker cards specifically.

### Tests

129 tests across 39 suites, all passing.

### Known limitations

- BottleArchive is utility-only; no Export/Import UI yet (Day 23/24).
- Update flow still points users at the release page — no in-place
  install until an Apple Developer ID lands.
- Apple GPTK fallback (when no CrossOver installed) still hits the
  WoW64 bug on certain installer classes — a Wine-upstream issue, not
  fixable from Fable.

## v0.2.0 — 2026-06-13

The "post-sprint roadmap" release. Closes items 7–15 of the original
1–15 backlog plus the wine-devel 11.10 upgrade and the Day 12
performance toggles.

### Headline

- **D3D12 via Apple's Game Porting Toolkit.** Pick a per-bottle graphics
  backend (`Off` / `DXMT` / `GPTK`). GPTK Wine is wine-devel 11.10 with
  D3DMetal 4.0 beta 1 overlaid from Apple's evaluation environment dmg —
  importable through Settings → Components.
- **Steam in one click.** "New Steam Bottle…" provisions the prefix,
  installs vcredist + corefonts, runs the upstream winetricks `steam`
  verb (which downloads Steam itself), and registers `Steam.exe` with
  the documented `-no-cef-sandbox` workaround.
- **Winetricks integration.** 500+ verbs browsable via "More from
  Winetricks…" in each bottle's Dependencies section. Single-script
  install with pinned sha256.
- **Wine upgraded to 11.10.** Both the standard Wine component and the
  GPTK backend now run wine-devel 11.10 (previously stable 11.0_1 / GPTK
  3.0-3's wine-7.7).

### Bottles

- Bottle templates with curated presets: Vanilla, Classic Games (D3D9),
  Modern Games (DXMT), Steam Ready, Cutting Edge (GPTK / D3D12). Each
  carries dependencies, winetricks verbs, and auto-registered games.
- "Duplicate Bottle" toolbar action — recursive prefix copy + reset
  identity. Refuses while games run in the source.
- Per-game graphics backend override — a D3D9 game and a D3D11 game can
  now share a bottle without fighting over the toggle.

### Performance

- Per-bottle performance toggles surfaced in `BottleDetailView`:
  - Metal Performance HUD (`MTL_HUD_ENABLED=1`)
  - MetalFX Upscaling (`D3DM_USE_METALFX_UPSCALER=1`, GPTK only)
  - Frame-rate cap — backend-agnostic, routes through DXMT_CONFIG or
    D3DM_FRAME_RATE_LIMIT depending on the active backend
- Live CPU% + resident memory per running game, sampled every 2 s via a
  `ps` process-tree walk.

### Storage & troubleshooting

- Disk-usage display per bottle (card footer + Storage section in detail
  view). Cached, scanned lazily on first appearance.
- "Clean Wine Temp Files…" — wipes `drive_c/windows/Temp` and each
  user's Temp/AppData/Local/Temp.
- "Force Kill Wine Processes…" — runs `wineserver -k` against the
  prefix, the escape hatch for hung games where Stop doesn't take.

### App

- In-app update checker polls GitHub releases for newer Fable builds
  (debounced once per hour). Banner offers Open Release Page / Skip
  This Version / Dismiss. Manual check from Settings → About.
- Localization scaffold: `defaultLocalization: "en"`, processed
  `en.lproj`/`es.lproj` resources, an `L10n` helper for non-View
  strings, and a real Spanish seed translation for the highest-traffic
  ~30 keys.

### Tests

114 tests across 37 suites, all passing.

### Known limitations

- Update flow points users at the release page; in-place updates need
  an Apple Developer ID + Sparkle (deferred until that's available).
- First Light installer still crashes the GPTK path at
  `alloc_pages_vprot`. The wine-11.10 upgrade did not fix it — needs a
  newer Wine base inside Apple's GPTK itself.

## v0.1.0 — 2026-06-12

Initial 10-day sprint release. Wine bottle management, DXMT 0.80 for
D3D11→Metal, dependency catalog (vcredist/OpenAL/DirectX), GOG/Inno
installer extraction via bundled innoextract, settings + config.json,
release packaging.
