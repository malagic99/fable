import SwiftUI

/// The at-a-glance verdict a cover carries in the Gamer interface: will this
/// game run? Synthesized from what Fable already knows — the recipe catalogs
/// (a match means someone verified this exact setup) and the quirk system's
/// anti-cheat findings. Honest by construction: no signal → unknown, never a
/// fake green.
enum GameConfidence: Equatable, Hashable, CaseIterable {
    /// A known-good recipe matches this game.
    case verified
    /// Known caveats (e.g. anti-cheat needs configuration).
    case caveat
    /// A known blocker — kernel anti-cheat that won't run under Wine.
    case blocked
    /// No signal either way.
    case unknown

    /// Verdict from the signals. A blocker always wins (an anti-cheat that
    /// won't run trumps a recipe for the game around it); then caveats; then
    /// a recipe match earns verified; otherwise unknown.
    /// The one entry point views should use — recipe lookup + quirk findings
    /// in one place, so the rule can't drift between call sites.
    @MainActor
    static func assess(_ game: Game, recipes: UserRecipeStore, quirks: QuirkService) -> GameConfidence {
        let hasRecipe = recipes.recipe(forExecutablePath: game.executablePath) != nil
            || GameRecipeCatalog.recipe(forExecutablePath: game.executablePath) != nil
        return assess(hasRecipe: hasRecipe, findings: quirks.findings(forGameNamed: game.name))
    }

    static func assess(hasRecipe: Bool, findings: [CompatibilityFinding]) -> GameConfidence {
        if findings.contains(where: { $0.severity == .knownBlocker }) { return .blocked }
        if findings.contains(where: { $0.severity == .caveat }) { return .caveat }
        if hasRecipe { return .verified }
        return .unknown
    }

    var tint: Color {
        switch self {
        case .verified: .green
        case .caveat: .orange
        case .blocked: .red
        case .unknown: .secondary
        }
    }

    var label: String {
        L10n.string("confidence.\(String(describing: self))")
    }
}
