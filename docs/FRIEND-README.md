# Fable — Windows games on your Mac

You got this from a friend. It's a small kit:

```
Fable-<version>.zip     the app
Steam Ready.fbottle     a ready-made "bottle" with Steam installed (optional)
Recipes/                per-game tested settings (optional)
README                  this file
```

## 1. Open the app (the one macOS hurdle)

Fable isn't notarized by Apple, so the **first** open needs one extra step —
otherwise macOS says it's "damaged" or from an "unidentified developer":

1. Unzip `Fable-<version>.zip` and drag **Fable.app** into `Applications`.
2. **Right-click** Fable.app → **Open** → click **Open** in the dialog.
   (Just double-clicking will NOT work the first time.)

If macOS still refuses, run this in Terminal and try again:

```
xattr -dr com.apple.quarantine /Applications/Fable.app
```

That's the only ritual. After the first open it behaves like any app.

## 2. First run

Fable's setup wizard walks you through everything. Two things it will ask for:

- **Wine** — downloaded automatically (~190 MB) when you create your first
  bottle. Nothing to do.
- **D3DMetal** (Apple's DirectX 12 graphics layer — the thing that makes
  modern games fast): Apple doesn't allow it to be bundled, so the wizard
  points you at **Sikarugir** (free): install it from
  https://github.com/Sikarugir-App/Sikarugir, **open it once** so it
  downloads its engine, and Fable finds everything itself. One-time.

## 3. Got a `.fbottle`? Import it and skip the slow part

A bottle is a self-contained Windows environment. The one in this kit already
has Steam installed and configured:

**Bottles → ＋ New Bottle tile → Import Bottle (.fbottle)…** → pick the file.

Then open the bottle, hit Play on Steam, log in with your account (scan the
QR with the Steam mobile app — fastest), and install your games.

## 4. Recipes

Double-click any `.fablerecipe` in the Recipes folder, or import them in
**Settings → Library → Shared Recipes**. A recipe applies a tested setup
(graphics backend + performance) automatically when you add that game.

## Good to know

- **Steam's own window is a bit sluggish.** Normal — it's software-rendered
  under translation on every Mac tool (paid ones too). Games are not: they
  render through Metal at full speed.
- **A game misbehaves?** Its page → Diagnose Last Run — Fable reads the log
  and tells you what's wrong in plain language.
- **Found a bug?** Settings → About → Send Feedback — it opens a pre-filled
  GitHub issue; nothing is sent without you seeing it.
- Spanish and Portuguese: Settings (Ajustes) → Appearance → Language.
