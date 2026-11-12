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
    /// Real tracked sessions on THIS Mac, no crash signatures. Claims
    /// exactly what we know — "it ran" — not "it's perfect": a game can
    /// accumulate playtime while rendering wrong (Absolute Drift's white
    /// screen taught that), so this never upgrades to verified on its own.
    case played
    /// No signal either way.
    case unknown

    /// Tracked playtime below this is a launch attempt, not evidence.
    static let playedEvidenceSeconds: Double = 15 * 60

    /// Why a verdict was reached — shown beside it, because a label alone
    /// asks to be trusted and this is what lets a player check it.
    enum Evidence: Equatable {
        case blocker(String)
        case caveat(String)
        /// A tested setup, and this bottle runs it.
        case recipe(name: String, backend: GraphicsBackend)
        /// A tested setup exists, but for a different backend than this one.
        case recipeForOtherBackend(tested: GraphicsBackend, current: GraphicsBackend)
        /// Tracked play on this Mac (on `engine`, when known), no crashes.
        case played(seconds: Double, engine: String?)
        /// Nothing to go on. `secondsElsewhere` is play on a different engine
        /// than the one in use now — real, but not evidence for this one.
        case none(secondsHere: Double, secondsElsewhere: Double, crashed: Bool)

        var text: String {
            switch self {
            case .blocker(let title), .caveat(let title):
                return title
            case .recipe(_, let backend):
                return L10n.string("evidence.recipe", backend.shortName)
            case .recipeForOtherBackend(let tested, let current):
                return L10n.string("evidence.recipe_other_backend", tested.shortName, current.shortName)
            case .played(let seconds, let engine):
                let time = Self.duration(seconds)
                if let engine {
                    return L10n.string("evidence.played_on", time, BottleRuntime.displayName(forEngineKey: engine))
                }
                return L10n.string("evidence.played", time)
            case .none(let here, let elsewhere, let crashed):
                if crashed { return L10n.string("evidence.crashed") }
                if elsewhere >= GameConfidence.playedEvidenceSeconds {
                    return L10n.string("evidence.played_other_engine", Self.duration(elsewhere))
                }
                if here > 0 { return L10n.string("evidence.little_play", Self.duration(here)) }
                return L10n.string("evidence.none")
            }
        }

        static func duration(_ seconds: Double) -> String {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
            return formatter.string(from: max(60, seconds)) ?? "\(Int(seconds / 60)) min"
        }
    }

    struct Assessment: Equatable {
        let confidence: GameConfidence
        let evidence: Evidence
    }

    /// The verdict with its reason, for one game in one bottle.
    @MainActor
    static func assessment(
        _ game: Game, in bottle: Bottle, recipes: UserRecipeStore, quirks: QuirkService,
        stats: GameStatsStore.Stats? = nil
    ) -> Assessment {
        let backend = game.graphicsBackend ?? bottle.graphicsBackend
        let recipe = recipes.recipe(forExecutablePath: game.executablePath)
            ?? GameRecipeCatalog.recipe(forExecutablePath: game.executablePath)
        return assessment(
            recipe: recipe, backend: backend,
            findings: quirks.findings(forGameNamed: game.name), stats: stats,
            engineKey: bottle.runtime?.engineKey(for: backend))
    }

    /// Pure, so the rules are tested without a bottle. Same order as
    /// ``assess(hasRecipe:findings:stats:)``, with two honesty rules on top:
    ///
    /// A recipe only earns `verified` when the game runs on the backend the
    /// recipe was tested on. Otherwise the green tick would vouch for a setup
    /// nobody tried — Ace Combat 8 is verified on Sikarugir 11 and crashes at
    /// Denuvo's first check on Wine 10. It reads as "works with tweaks": the
    /// tweak is switching backend.
    ///
    /// Play time only counts on the engine in use now. A bottle moved to a
    /// newer engine has not been played there.
    static func assessment(
        recipe: GameRecipe?, backend: GraphicsBackend?, findings: [CompatibilityFinding],
        stats: GameStatsStore.Stats? = nil, engineKey: String? = nil
    ) -> Assessment {
        if let blocker = findings.first(where: { $0.severity == .knownBlocker }) {
            return Assessment(confidence: .blocked, evidence: .blocker(blocker.title))
        }
        if let caveat = findings.first(where: { $0.severity == .caveat }) {
            return Assessment(confidence: .caveat, evidence: .caveat(caveat.title))
        }
        if let recipe {
            guard let backend, backend != recipe.backend else {
                return Assessment(
                    confidence: .verified,
                    evidence: .recipe(name: recipe.name, backend: recipe.backend))
            }
            return Assessment(
                confidence: .caveat,
                evidence: .recipeForOtherBackend(tested: recipe.backend, current: backend))
        }
        let crashed = !(stats?.crashSignatures ?? [:]).isEmpty
        let here = stats?.evidenceSeconds(onEngine: engineKey) ?? 0
        if here >= playedEvidenceSeconds, !crashed {
            return Assessment(confidence: .played, evidence: .played(seconds: here, engine: engineKey))
        }
        let elsewhere = max(0, (stats?.totalSeconds ?? 0) - here)
        return Assessment(
            confidence: .unknown,
            evidence: .none(secondsHere: here, secondsElsewhere: elsewhere, crashed: crashed))
    }

    /// Verdict from the signals. A blocker always wins (an anti-cheat that
    /// won't run trumps a recipe for the game around it); then caveats; then
    /// a recipe match earns verified; then real observed sessions; otherwise
    /// unknown.
    /// The one entry point views should use — recipe lookup + quirk findings
    /// in one place, so the rule can't drift between call sites.
    @MainActor
    static func assess(
        _ game: Game, recipes: UserRecipeStore, quirks: QuirkService, stats: GameStatsStore.Stats? = nil
    ) -> GameConfidence {
        let hasRecipe = recipes.recipe(forExecutablePath: game.executablePath) != nil
            || GameRecipeCatalog.recipe(forExecutablePath: game.executablePath) != nil
        return assess(hasRecipe: hasRecipe, findings: quirks.findings(forGameNamed: game.name), stats: stats)
    }

    static func assess(
        hasRecipe: Bool, findings: [CompatibilityFinding], stats: GameStatsStore.Stats? = nil
    ) -> GameConfidence {
        if findings.contains(where: { $0.severity == .knownBlocker }) { return .blocked }
        if findings.contains(where: { $0.severity == .caveat }) { return .caveat }
        if hasRecipe { return .verified }
        if let stats,
           stats.totalSeconds >= playedEvidenceSeconds,
           (stats.crashSignatures ?? [:]).isEmpty {
            return .played
        }
        return .unknown
    }

    var tint: Color {
        switch self {
        case .verified: .green
        case .caveat: .orange
        case .blocked: .red
        case .played: .blue
        case .unknown: .secondary
        }
    }

    var label: String {
        L10n.string("confidence.\(String(describing: self))")
    }
}
