# Cold-Start Dry-Run Checklist (the 1.0 gate)

Goal: prove a stranger's first hour works, using a **fresh macOS user
account** on this Mac. A fresh account shares `/Applications` but has its own
`~/Library` — which is exactly the surface Fable and Sikarugir live on, so it
simulates a friend's machine for everything except hardware and Gatekeeper
quarantine (see step 0).

Pre-audited (2026-07-12): no hardcoded dev paths in Sources; Wine downloads
on first bottle (~190 MB, needs network); version catalog is bundled (offline-
safe); update checker points at malagic99/fable; the dead `sikarugir.app` URL
and the stale Sikarugir GitHub org were fixed — wizard and FRIEND-README now
point at github.com/Sikarugir-App/Sikarugir and say to **open Sikarugir once**
so it downloads its engine.

## 0. Setup (10 min)

- [ ] System Settings → Users & Groups → add user `fabletest` (Standard).
- [ ] Build the real artifact: `./scripts/make-app.sh`, then zip it exactly
      like a release (`ditto -c -k --sequesterRsrc --keepParent Fable.app
      Fable-test.zip`). **Test the zip, not your dev build.**
- [ ] Copy the zip into `/Users/Shared/` (visible to the new account).
- [ ] Re-quarantine so Gatekeeper behaves like a real download:
      `xattr -w com.apple.quarantine "0083;00000000;Safari;" Fable-test.zip`
      (a plain local copy has no quarantine → you'd skip the "damaged app"
      hurdle a friend WILL hit).
- [ ] Log into `fabletest` (fast user switching is fine).

## 1. Gatekeeper ritual (FRIEND-README §1)

- [ ] Unzip, drag Fable.app to Applications (expect a password prompt as
      Standard user — note if this is confusing).
- [ ] Double-click first: confirm macOS blocks it (this is what a friend sees).
- [ ] Right-click → Open → Open: app launches.
- [ ] If macOS still refuses: does the README's `xattr -dr` line work as
      written? (Copy-paste it exactly.)

## 2. Onboarding wizard, step by step

- [ ] Welcome → shows, Get Started advances, Skip works (but don't skip).
- [ ] Interface step → pick Gamer (the friend default), confirm previews render.
- [ ] **Graphics step — the risky one.** Expected on a fresh account:
      status = *missing* (Sikarugir's engine lives in per-user
      `~/Library/Application Support/Sikarugir`, which doesn't exist here even
      though /Applications has the app).
  - [ ] "Get Sikarugir" opens github.com/Sikarugir-App/Sikarugir ✓ (fixed today)
  - [ ] Install/open Sikarugir once in this account → its engine downloads.
  - [ ] Back in Fable: **Re-check** flips to *notInstalled(available)*.
  - [ ] "Set Up D3DMetal" → extracts → *ready*. Time it (friend patience data).
- [ ] Source step → pick Steam.
- [ ] First-bottle step → Create Bottle → template pre-picked = Steam Ready.
  - [ ] Wine auto-download kicks in (~190 MB) with visible progress.
  - [ ] Winetricks verbs run; if a mirror fails, the toast says retry — not a
        destroyed bottle (v0.6.1 behavior).
  - [ ] Steam installs (big download — note total wall-clock).
- [ ] Done step shows; "Start Playing" closes the wizard and never re-shows
      on relaunch.

## 3. First real session

- [ ] Steam opens (CEF renders — no black squares), QR login works.
- [ ] Install a small game; the install COMMITS (watch for the auto-commit
      heal on Steam exit if it stalls).
- [ ] Launch it, play 10 minutes, quit. Playtime + "played" dot appear.
- [ ] Diagnose Last Run on a healthy session says something sane.

## 4. Friend Kit extras (if time)

- [ ] Import the donor `.fbottle` on the fresh account (this doubles as the
      Rock-2 "real donor export" validation — export it from the main account
      first, note duration + disk headroom).
- [ ] Double-click a `.fablerecipe` → imports.
- [ ] Settings → Language → Español → relaunch → wizard/UI reads translated.

## 5. Teardown + capture

- [ ] Write down every hesitation, wrong expectation, or missing string —
      each one is a 1.0 blocker or a FRIEND-README line.
- [ ] Copy `~/Library/Application Support/Fable/Logs` out of the test account
      before deleting it.
- [ ] Delete the `fabletest` account when done (or keep it for regression
      dry-runs per release).

## Known gaps this dry-run does NOT cover

- **Real Gatekeeper on a different Mac** — quarantine simulation is close but
  not identical to a Safari download on other hardware.
- **Different Apple Silicon generation** (M1/M2 friend hardware).
- **Localized-headline gap**: the graphics step's status headlines are built
  as Swift `String`s, so they render English even in es/pt. Known, deliberate
  for now — same class as Doctor prose (roadmap fill-in).
