# Localization

Fable ships in English, Spanish, and Portuguese. Coverage is **enforced by
tests** — `LocalizationCoverageTests` scans the source tree and fails naming
the exact strings you forgot, so a missing translation breaks the build
instead of silently rendering English.

## How strings resolve (two mechanisms)

1. **View literals** — `Text("Delete Bottle")`, `Button("…")`, `Toggle`,
   `Picker`, `Section`, `Label`, `LabeledContent`, `TextField`, `Link`,
   `.help("…")`, `prompt: Text("…")`. SwiftUI treats the literal as a
   `LocalizedStringKey`: the English text **is** the key, looked up in
   `Localizable.strings` at render time. No code changes needed — just add
   the entry to `es.lproj` and `pt.lproj`.

2. **Code-built strings** — anything constructed in Swift (enum
   `displayName`s, ternaries, interpolations, `StatusBadge(text:)`, toasts).
   These are plain `String`s and do NOT auto-localize. Route them through
   `L10n.string("dotted.key")` (or `L10n.string("key", args…)` for
   printf-style formats) and add the dotted key to **all three** `.strings`
   files.

   The trap to know: `Text(flag ? "On" : "Off")` is a `String` ternary — it
   silently skips localization even though each branch looks like a literal.
   Same for `.help(condition ? "A" : "B")`. Use `L10n.string` there.

## Adding a new UI string (the 30-second version)

1. Write the English literal in the view.
2. Add the same key to `Sources/Fable/Resources/es.lproj/Localizable.strings`
   and `pt.lproj/Localizable.strings`:
   ```
   "Delete Bottle" = "Eliminar botella";
   ```
   Proper nouns and units ("D3DMetal", "120 fps") still need a line — value
   = key is fine and keeps the coverage test exception-free.
3. `swift test --filter LocalizationCoverageTests` tells you if you missed one.

## Adding a new language

1. Copy `Sources/Fable/Resources/en.lproj` → `<code>.lproj` and translate.
2. Register it in `Package.swift` under `resources:`
   (`.process("Resources/<code>.lproj")`).
3. Add a case to `AppLanguage` (Components/AppLanguage.swift) so it appears
   in Settings → Appearance → Language.
4. Add the code to the language lists in `LocalizationTests` and
   `LocalizationCoverageTests` so the gates cover it.

## Conventions

- es uses **tú**, pt uses **você** (pt-BR vocabulary: Mesa, controle, capa).
- Established terminology — keep it consistent:
  bottle = botella / garrafa · wall = muro / mural · cover = carátula / capa ·
  frame cap = límite de FPS / limite de FPS · trigger = gatillo / gatilho.
- Technical identifiers stay English everywhere: backend names (DXMT,
  Sikarugir), DXMT log levels, `KEY=VALUE` env syntax, winetricks verb names.
- The language switch writes the standard `AppleLanguages` override and
  applies on next launch (`AppLanguage.apply`).
