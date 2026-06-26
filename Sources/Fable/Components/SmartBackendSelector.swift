import Foundation

/// Decides whether Fable should auto-pick a graphics backend for a game so an
/// unconfigured bottle "just works" without the user reading the compatibility
/// banner and clicking "Use X".
///
/// Deliberately conservative — it only acts on **strong signal** and only on a
/// bottle the user hasn't touched. The compatibility banner still *suggests*
/// for the ambiguous cases (a clean install with no markers); auto-pick won't
/// silently override the default there.
enum SmartBackendSelector {
    /// Auto-pick is allowed only when the user hasn't set a per-game backend
    /// *and* the bottle is still on the untouched default (`.off` / wined3d).
    /// A Steam/template bottle already carries a deliberate backend, and a
    /// per-game override is an explicit user choice — never stomp either.
    static func canAutoPick(game: Game, bottleBackend: GraphicsBackend) -> Bool {
        game.graphicsBackend == nil && bottleBackend == .off
    }

    /// A validated recipe's backend — the authoritative, synchronous fast path
    /// (no filesystem scan). nil = no recipe, leave the default alone.
    ///
    /// DXVK recipes are intentionally excluded: DXVK needs a one-time per-bottle
    /// install, which is a visible action better left to the banner's explicit
    /// "Use DXVK → installing…" flow than done silently at launch.
    static func recipeBackend(game: Game, bottleBackend: GraphicsBackend) -> GraphicsBackend? {
        guard canAutoPick(game: game, bottleBackend: bottleBackend),
              let recipe = GameRecipeCatalog.recipe(forExecutablePath: game.executablePath),
              isSelfSufficient(recipe.backend) else { return nil }
        return recipe.backend
    }

    /// A backend justified by compatibility markers that simply won't render on
    /// wined3d — NVIDIA Streamline, DirectStorage, or a Denuvo/anti-tamper
    /// layer all imply a modern D3D path. Requires a completed scan. nil = no
    /// strong signal (a clean install), leave the default and let the banner
    /// suggest.
    static func markerBackend(
        game: Game,
        bottleBackend: GraphicsBackend,
        findings: [CompatibilityFinding],
        crossOverAvailable: Bool,
        sikarugirAvailable: Bool
    ) -> GraphicsBackend? {
        guard canAutoPick(game: game, bottleBackend: bottleBackend) else { return nil }
        let ids = Set(findings.map(\.id))
        let needsModern = ids.contains("streamline")
            || ids.contains("directstorage")
            || ids.contains("denuvo-heuristic")
        guard needsModern,
              let rec = CompatibilityScanner.recommendedBackend(
                for: findings,
                crossOverAvailable: crossOverAvailable,
                sikarugirAvailable: sikarugirAvailable
              ),
              isSelfSufficient(rec) else { return nil }
        return rec
    }

    /// Backends that need no extra per-bottle setup before launch. DXVK is the
    /// odd one out (winetricks install), so it's not eligible for silent
    /// auto-pick; everything else routes through its own discovered engine.
    private static func isSelfSufficient(_ backend: GraphicsBackend) -> Bool {
        switch backend {
        case .dxvk: false
        case .off, .dxmt, .gptk, .crossover, .sikarugir: true
        }
    }
}
