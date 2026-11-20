# Security scan — 20 November 2026

Scope: everything changed since the first audit (`docs/SECURITY-AUDIT-2026-11.md`, at `26f6733`) — about 6,200 lines in 75 files — plus a re-check of that audit's claims. `main` at `48b2ef5` (v1.3.1). Three independent reviewers read the code (untrusted-data parsers; downloads and processes; privacy and data); every finding below was then checked again.

**Status:** findings 1–5 are fixed — 1 and 3 in **v1.3.2**, 2, 4 and 5 in **v1.3.3** (both released 2026-11-20). This report stayed out of the public repository until they had shipped. Findings 6–14 are open. Checking the donor-export fix on a real bottle also turned up a bug outside the scan's list; it's described under "Found while fixing" below.

Threat model unchanged from the first audit: Wine is not a sandbox, so "a bottle runs Windows code" is not a finding. Findings are things that go further — file access outside the bottle without launching anything, crashes from crafted input, or behaviour contrary to what the interface promises.

## Findings

| # | Severity | Finding | How it was checked | Status |
|---|---|---|---|---|
| 1 | **High** | **Opening an imported bottle can replace or delete files anywhere in your home folder.** When a bottle's page opens, Fable "finishes stuck Steam installs" (`SteamInstallCommitter`). It takes the game's folder name from the bottle's `appmanifest_*.acf` without checking it, so a name like `../../../…` points outside the bottle, and Fable deletes same-named files there and moves the bottle's files in. A crafted `.fbottle` could, for example, replace `~/.zshrc` or put a file in `~/Library/LaunchAgents` (code at next login). No game has to be launched; clicking the bottle is enough. Pre-dates the first audit (it missed it). | **Reproduced** in a temp folder: a file outside the fake Steam folder was replaced. `SteamInstallCommitter.swift:60,77-78,180-189`, triggered from `BottleDetailView.swift:48`. | **Fixed in v1.3.2** ([#134](https://github.com/malagic99/fable/pull/134)): the folder name must be a single folder, the destination must resolve inside Steam's folder with no symlink out, oversized manifests are skipped. |
| 2 | Medium | **Donor exports still carry the owner's Steam account name.** "Donor for a Friend (no games, no login)" strips the login folders but not the Windows registry (`user.reg`), where Steam keeps `AutoLoginUser`. That contradicts the promise in the export sheet, README and notices. | Confirmed: the field is present in the real bottle; `BottleArchive.swift:80-98` doesn't cover it. | **Fixed in v1.3.3** ([#135](https://github.com/malagic99/fable/pull/135)): the account name, signed-in account and installed-app keys are removed from a copy-on-write clone's registry. |
| 3 | Medium | **Opening a crafted bottle can crash Fable.** The Steam manifest parser has no nesting limit; a ~100 KB `.acf` nested 20,000 deep overflows the stack of the background task that reads it. Same trigger as #1 (opening the bottle). | Reproduced by the reviewer (crash at 20,000 levels, fine at 2,000). `SteamKeyValues.swift:121-141`. | **Fixed in v1.3.2** ([#134](https://github.com/malagic99/fable/pull/134)): nesting capped at 64 levels. |
| 4 | Medium | **Donor exports don't strip Steam-bridge games.** They're downloaded to `drive_c/SteamBridge/<id>`, which neither the exclusion list nor the "remove games" step covers, so licensed game files ship in a "no games" export. Not happening yet: both real bottles' bridge folders are empty. | Confirmed by reading `BottleArchive.swift:104-113`, `SteamCmd.swift:123`. | **Fixed in v1.3.3** ([#135](https://github.com/malagic99/fable/pull/135)): the folders of all games outside Steam's are left out, Windows' own programs kept. |
| 5 | Low | Donor exports carry the owner's list of installed Steam app ids (`steamSyncedAppIDs`, new in #133), and on the friend's Mac those games are then never added automatically. | Confirmed by reading. | **Fixed in v1.3.3** ([#135](https://github.com/malagic99/fable/pull/135)). |
| 6 | Low | **The 30-second Steam auto-add rescans the whole library every time.** The "unchanged library is cheap" check runs *after* the full scan, so it never saves anything; a bottle with a huge manifest causes a memory spike every 30 s. The string-table size in Steam's cache is also trusted up to 5 million entries before allocating. | Confirmed by reading `BottleManager.swift:288-292`, `SteamAppInfoCache.swift:39-41`. Introduced in #133. | Open. |
| 7 | Low | Steam's app cache is memory-mapped; if Steam rewrites it in place during a scan, Fable could crash (SIGBUS). | Plausible, not tested. `SteamAppInfoCache.swift:74`. | Open. |
| 8 | Low | A malformed benchmark result (`frames=inf`) crashes Fable. Only reachable through Fable's own test program or a tampered engine. | Confirmed by reading `EngineBenchmark.swift:153`. | Open. |
| 9 | Low | Engine repairs copy support libraries from the Sikarugir app's folder (pre-v1.2 installs only) without checking them, then record the result as the engine's new known-good state, so the integrity check can't flag them later. | Confirmed by reading `SikarugirManager.swift` backfill + rerecord. | Open. |
| 10 | Low | If the installer-engine download fails, 32-bit installers silently fall back to another app's unverified Wine (e.g. Whisky's Wine 7.7). | Confirmed by reading `GameInstaller.swift:111-115`. | Open. |
| 11 | Low | Two installs of the same component at once can collide (shared download file and destination) → a failed or half-built engine. Bytes are always the pinned file, so nothing can be swapped in. | Plausible. `ComponentManager.swift:91-181`. | Open. |
| 12 | Low | **Release provenance says more than it proves:** the bundled `cabextract`/`innoextract` come from whatever Homebrew has installed (no version or hash pinned), are hashed only after re-signing, and innoextract's 13 bundled libraries aren't hashed at all. The make-app comment calls the record "covered by the signature", but the app is ad-hoc signed. | Confirmed by reading `make-app.sh`, `build-info.py`. | Open. |
| 13 | Low | Settings says the update check is "the only network call Fable makes on its own", but cover art (on by default) also searches Steam's store by game name, including non-Steam games, and a new Steam API call was added. | Confirmed by reading `SettingsManager.swift:97`, `GameArtwork.swift:24`. | Open. |
| 14 | Low | Fable now starts a Steam sign-in (steamcmd, in Terminal) for the bridge. The password never reaches Fable, but steamcmd will cache a session token in `Components/steamcmd/config`, and nothing discloses or clears it. The first audit's "Fable handles no login flows" no longer holds strictly. | Confirmed by reading `SteamCmd.swift:126-150`; no token cached yet. | Open. |

## Found while fixing

**Real bottles could never be imported** (fixed in v1.3.3, [#135](https://github.com/malagic99/fable/pull/135)). An import re-checksums the unpacked bottle before trusting it, but the checksum covered the raw tar stream: extended attributes (macOS adds `com.apple.provenance` when files are written, and `user.DOSATTRIB` can be lost), owner names, and permission bits the umask strips on extraction. So a real bottle's export always failed its own check; only the tiny test bottles passed. The first audit had recorded real donor export as "unit-tested only". Manifests now record `checksumFormat: 2`, computed without attributes, ACLs, file flags or owner names, and import keeps permission bits (`tar -p`); archives without the field are checked the old way. Verified with a donor export of a real 166 GB Steam bottle: 1.3 GB, about 20 seconds, the import's check passes, and no account name is inside.

## Info (no action needed now)

- Auto-added Steam games and Fable's "inside the bottle" check are lexical, so a symlinked game folder could point outside the bottle. Still needs the user to press Play; an imported bottle could already carry such an entry.
- Engine pins and component versions become folder names without validation. Not reachable today (imports drop pins, git tags can't contain `..`); cheap to harden.
- `release.sh` pushes the tag before it builds and checks; a refused publish leaves a tag without a release.
- A canary or benchmark interrupted by quitting Fable leaves its throwaway prefix and Wine processes behind.
- steamcmd updates itself from Valve after the pinned bootstrap; only the bootstrap is verified.
- Choosing the experimental GPTK 4 renderer ad-hoc re-signs Apple's framework.
- Launch logs now print renderer/Wine environment values and more home-folder paths. Logs still never leave the Mac.
- A test file and the app's bundle identifier contain the developer's name. Nothing else personal was found in the 304 tracked files; the 2.7 MB standalone website file's embedded image wasn't inspected.

## Checked and clean

- Component downloads: every `versions.json` entry is SHA-256-pinned; verification fails closed; extraction is staged and moved atomically; bsdtar without `-P`.
- Steam app-cache reader: bounds-checked, depth-capped; 200,000 random inputs produced no crash or hang.
- Auto-add path rules: folder names with `/`, `\`, `.` or `..` and executables that climb out are refused.
- `MachORpath`, `RuntimeManifest` (symlinks recorded, not followed), canary output parsing.
- `SteamCmd.downloadCommand` shell quoting; the Rosetta installer (absolute path, explicit button, licence notice in all three languages).
- The committed canary programs rebuild byte-for-byte to `canary/SHA256SUMS`.
- `build-info.json` and the release provenance hold no paths, user names or machine names; `release.sh` refuses a dirty tree.
- Re-checked from the first audit: Feedback/Share send nothing and contain no paths — **holds**. Logs never leave the Mac — **holds**. Recipes carry no paths — **holds**. Archive extraction is safe — **holds**. Donor strips the Steam login — **did not fully hold** (#2, #4; fixed in v1.3.3). No login flows — **no longer strictly true** (#14).

## Still open from the first audit

Unchanged: Microsoft redistributables unverified (Authenticode check needed); the `in-app-updater` branch must be audited before merging; a GitHub digest proves transport, not origin; two Doctor rules untested.

## What's next

1. **#6–#8**: bugs in code added the week before the scan — fingerprint the Steam library before scanning it, read the app cache instead of mapping it, reject non-finite benchmark numbers.
2. **#9–#14** as small follow-ups; #12 and #13 are mostly wording.

Every fix shipped so far comes with tests that were run against the code before the fix and failed there.
