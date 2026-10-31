# Sprint 1 security audit — November 2026

Scope: the workflows Fable uses to bring outside data onto a Mac — bottle
import/export (`.fbottle`), themes (`.fableskin`), recipes (`.fablerecipe`),
component downloads, Heroic import, per-game launch settings and desktop
shortcuts — plus what Fable logs and sends, and how far Game Doctor's rules
are tested.

Baseline before any change: `main` at `f1c9000`, **494 tests in 103 suites,
all passing**.

## Threat model in one paragraph

Wine is not a sandbox. Windows code in a bottle can read and write your files
through the `Z:` drive and can start native programs. So "a shared bottle runs
code" is not, by itself, a finding: running a friend's bottle means trusting
that friend. The findings below are the cases that go *further* — code or file
access that happens without launching anything, outside the folder the user
picked, or contrary to what the UI promises. Severity reflects that.

## Findings

| # | Severity | Finding | Files | Status |
|---|---|---|---|---|
| 1 | High | Importing a `.fableskin` could write outside the themes folder (its `id` became a file name) and, via `backgroundImageFile`, copy any readable file into a theme you'd re-export and share. | `ThemeStore.swift`, `FableSkin.swift` | Fixed — [#93](https://github.com/malagic99/fable/pull/93) |
| 2 | Medium | An empty SHA-256 skipped download verification, and updates found on GitHub got an empty one when the asset had no digest. | `ChecksumVerifier.swift`, `ComponentManager.swift`, `WinetricksManager.swift`, `UpdateManager.swift` | Fixed — [#94](https://github.com/malagic99/fable/pull/94) |
| 3a | Medium | Per-game environment from an imported bottle was applied verbatim: `DYLD_INSERT_LIBRARIES` loads a dylib into Wine; `WINELOADER`/`WINESERVER`/`WINEDLLPATH` pick native binaries. | `GameLauncher.swift`, `WineEnv.swift` | Fixed — [#95](https://github.com/malagic99/fable/pull/95) |
| 3b | High | Desktop shortcuts wrote environment variable *names* unquoted into a shell script, so a crafted name ran as a command whenever the shortcut opened — no game needed. | `ShortcutGenerator.swift` | Fixed — [#95](https://github.com/malagic99/fable/pull/95) |
| 4 | **High** | "Donor for a Friend (no games, no login)" exports carried the owner's Steam login: `AppData/Local/Steam/local.vdf` (ConnectCache, the saved login token) and `htmlcache` cookies (`steamLoginSecure` for store, checkout, community). Confirmed present in the real Steam bottle on the developer's Mac. | `BottleArchive.swift` | Fixed — [#96](https://github.com/malagic99/fable/pull/96). **User action if a donor was ever shared:** Steam → Settings → Security → Manage Steam Guard → Deauthorize all other devices. |
| 5 | Low | A game entry from an imported bottle could launch an executable outside `drive_c` (`../..`); Heroic import used Heroic's `folder_name`/`executable` unchecked, placing links elsewhere in the bottle. | `GameLauncher.swift`, `BottleManager.swift` | Fixed — [#97](https://github.com/malagic99/fable/pull/97) |
| 6 | Low | The `.fbottle` checksum was described as tamper detection. It's integrity only: the manifest travels inside the same archive, so anyone repacking a bottle can recompute it. Extraction itself is safe (bsdtar refuses `..` and absolute paths by default). | `BottleArchive.swift` | Comment corrected in this PR; no code change needed. |

Every fix ships with tests that **fail against the code before the fix** —
each PR was checked that way, which caught two tests that would otherwise have
passed vacuously (a `../` path only resolves through a directory that exists).

## Checked and clean

- **Recipes (`.fablerecipe`).** A recipe carries only the exe's file name,
  backend, frame cap, MetalFX flag and a note. No paths, no environment, no
  user name. The stored file name is sanitised.
- **Send Feedback / Share This Setup.** Nothing is sent by the app; a browser
  opens a pre-filled GitHub issue for review. The system block is app version,
  macOS version and hardware summary — no serials, user names or paths.
- **Logs.** Game logs are Wine's own output and contain home-folder paths (and
  therefore the Mac user name), but they never leave the Mac: there's no path
  that attaches or uploads them. Fable itself logs two `NSLog` lines (settings
  save, startup directory) with no personal data. The note #95 adds lists
  refused variable *names* only, never values.
- **Steam credentials in code.** Fable's source handles no Steam passwords,
  tokens or login flows. (The private EFT kit outside the repo does; out of
  scope.)
- **Archive extraction.** `.fbottle` unpack uses `/usr/bin/tar` (bsdtar),
  which strips absolute paths and refuses `..` entries unless `-P` is passed;
  Fable doesn't pass it. Verified with a crafted tar: the `..` entry is
  refused, the absolute one lands inside the target, and tar exits non-zero,
  which Fable treats as a failed import.

## Game Doctor coverage

- 29 rules: 28 match on log text, 1 (`doctor-cross-backend`) on crash
  signatures across backends, which has its own test.
- 26 of the 28 log rules have at least one of their trigger strings in
  `GameDoctorTests`. Untested: **`dwrite-cef`** and **`d3d11-device`**.
  (String-presence is a proxy — it shows a trigger is exercised, not that every
  trigger is.)
- Log reads are capped at the last 4 MB, so a runaway log can't stall the
  Doctor. Largest real log on the dev Mac: 147 KB.
- **Accuracy gap:** the `anticheat` rule matches any `easyanticheat` string and
  says "kernel-level, can't run". The Epic Online Services edition (e.g. Ace
  Combat 8's `EasyAntiCheat_EOS`) is user-mode. Whether it runs under macOS
  Wine is **unverified** (its official support is Proton on Linux), so the
  verdict may be right in practice but the stated reason is wrong. Belongs with
  Sprint 3's compatibility data rather than a rule tweak now.

## Still open

1. **Windows redistributables are downloaded unverified** — VC++ x64/x86,
   DirectX June 2010, OpenAL (`DependencyCatalog`). HTTPS only. Pinning a hash
   doesn't work for `aka.ms` links, which always serve Microsoft's latest
   build. The real fix is checking the Authenticode signature (Microsoft
   signer) before running the installer — a separate piece of work. *Medium.*
2. **In-app updater** (`origin/in-app-updater`, unmerged) downloads and
   replaces Fable.app. It will be the most sensitive code path in the app;
   audit it before it merges. *Must-do before merge.*
3. **A GitHub digest proves transport integrity, not origin.** A compromised
   upstream release (Gcenx Wine builds, DXMT) would carry a valid digest. No
   cheap fix; noted so nobody reads #94 as more than it is.
4. **Doctor:** add tests for `dwrite-cef` and `d3d11-device`; revisit the
   EAC-EOS wording with Sprint 3 data.

## Test results

| | Tests | Result |
|---|---|---|
| Baseline (`main`, `f1c9000`) | 494 | all pass |
| #93 `.fableskin` | 498 | all pass |
| #94 checksums | 498 | all pass |
| #95 launch environment | 499 | all pass |
| #96 donor export | 494 (existing test extended) | all pass |
| #97 path containment | 496 | all pass |

Combined once merged: 494 + 4 + 4 + 5 + 2 = **509** tests. The PRs touch
separate code; they conflict only on the top of `CHANGELOG.md`'s Unreleased
section.

## Recommendations for Sprint 2

- Merge #96 first (it's the one with real-world exposure), then the rest.
- Settle the November slot: this plan and Rock 3 (native Steam bridge) both
  claim it in `docs/ROADMAP.md`.
- For benchmarking, start from what exists: the Metal performance HUD toggle
  (`MTL_HUD_ENABLED`) is wired per bottle, but nothing reads its frame-time
  output, and DXVK's own HUD/frame-time logging isn't wired at all. Agree the
  measurement method before building storage or a comparison UI on top of it.
