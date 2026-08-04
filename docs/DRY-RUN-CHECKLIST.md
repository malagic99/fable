# Cold-Start Dry-Run Checklist (the 1.0 gate)

Goal: prove a stranger's first hour works, using a **fresh macOS user
account** on this Mac. A fresh account shares `/Applications` but has its own
`~/Library` — which is exactly the surface Fable and Sikarugir live on, so it
simulates a friend's machine for everything except hardware and Gatekeeper
quarantine (see step 0).

Pre-audited (2026-07-12, still valid at v0.23.1): no hardcoded dev paths in
Sources; Wine downloads on first bottle (~190 MB, needs network); version
catalog is bundled (offline-safe); update checker points at malagic99/fable;
the dead `sikarugir.app` URL and stale Sikarugir GitHub org were fixed — wizard
and FRIEND-README point at github.com/Sikarugir-App/Sikarugir and say to **open
Sikarugir once** so it downloads its engine. Website is live at
https://malagic99.github.io/fable/.

Testing **v0.23.1**, pulled from GitHub **exactly as a stranger would** — no
local build, no faked quarantine. Safari applies the real Gatekeeper quarantine,
so this is the most faithful version of the test.

## 0. Setup (5 min) — get it the way a stranger does

Do everything **from the fresh account's own browser**. That's the whole point:
the real download path + real quarantine, nothing simulated.

- [ ] System Settings → Users & Groups → add a **Standard** user `fabletest`;
      log into it (fast user switching is fine).
- [ ] In `fabletest`, open **Safari** → **https://malagic99.github.io/fable/** →
      the Download button (or straight to
      **github.com/malagic99/fable/releases/latest** → `Fable-0.23.1.zip`).
  - [ ] Does download → "now what?" feel obvious with zero prior context? Note
        any moment you'd have to *tell a friend* what to do next.

## 1. Gatekeeper ritual (FRIEND-README §1) — the #1 friend-stopper

- [ ] Unzip (Safari may auto-unzip), drag `Fable.app` to `/Applications`
      (expect an admin password prompt as a Standard user — note if confusing).
- [ ] **Double-click it first** → macOS should block it ("damaged" / unidentified
      developer). This is exactly what a friend hits — is it alarming?
- [ ] Right-click → **Open** → **Open** → app launches.
- [ ] If it still refuses, does the FRIEND-README's `xattr -dr com.apple.quarantine`
      line work copy-pasted verbatim? (This is the real fallback now, not a sim.)

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

## Results log (fill this in as you go — don't trust memory)

One row per friction point, **at the moment it happens**. "Clean" rows count
too — they're the proof. Severity: **blocker** (stranger is stuck) /
**confusing** (worked, but needed prior knowledge) / **cosmetic**.

| # | Where | What tripped you (or "clean") | Severity | Fix / README line |
|---|-------|-------------------------------|----------|-------------------|
| 1 | Website → download | | | |
| 2 | Gatekeeper ritual | | | |
| 3 | Wizard: interface | | | |
| 4 | Wizard: graphics / Sikarugir | | | |
| 5 | Wizard: Wine download | | | |
| 6 | Wizard: Steam install | | | |
| 7 | First game session | | | |
| 8 | (anything else) | | | |

Reading the table afterwards: every **blocker** is a 1.0 gate — fix before
tagging. Every **confusing** becomes a FRIEND-README line (that doc exists so
you never have to be in the room). **Cosmetic** goes to the roadmap fill-in
list, not the gate.

## Known gaps this dry-run does NOT cover

- **Real Gatekeeper on a different Mac** — quarantine simulation is close but
  not identical to a Safari download on other hardware.
- **Different Apple Silicon generation** (M1/M2 friend hardware).
- **Localized-headline gap**: the graphics step's status headlines are built
  as Swift `String`s, so they render English even in es/pt. Known, deliberate
  for now — same class as Doctor prose (roadmap fill-in).
