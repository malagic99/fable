import SwiftUI

/// How a game is expected to behave, as shown to the player.
///
/// This is the presentation of ``GameConfidence``, not a replacement for it.
/// Confidence answers "what do we know about this game"; `Health` answers "what
/// should the player see", which needs two things confidence deliberately
/// doesn't model: whether the game is native (no Wine involved at all) and
/// whether it crashed on *this* Mac recently.
///
/// Every state carries a glyph and a label as well as a colour. The badge this
/// feeds replaced a bare coloured dot, which put the entire verdict in hue —
/// and the palette was green/amber/red, the exact combination that fails for
/// the ~8% of men with red-green colour deficiency.
enum Health: Equatable, CaseIterable {
    case native
    case blocked
    case crashed
    case verified
    case tweaks
    case played
    case untested

    var tint: Color {
        switch self {
        case .verified: .green
        case .tweaks, .crashed: .orange
        case .blocked: .red
        // Cyan rather than blue: blue now means "native Mac game", and two
        // states sharing a hue is what made the dot ambiguous.
        case .played: .cyan
        case .untested: .secondary
        case .native: .blue
        }
    }

    var symbol: String {
        switch self {
        case .verified: "checkmark"
        case .tweaks, .crashed: "exclamationmark"
        case .blocked: "xmark"
        case .played: "clock.arrow.circlepath"
        case .untested: "questionmark"
        case .native: "applelogo"
        }
    }

    var labelKey: String {
        switch self {
        case .verified: "health.verified"
        case .tweaks: "health.tweaks"
        case .blocked: "health.blocked"
        case .played: "health.played"
        case .untested: "health.untested"
        case .crashed: "health.crashed"
        case .native: "health.native"
        }
    }

    var label: String { L10n.string(labelKey) }

    /// True while the badge is reporting something that happened on this Mac
    /// rather than a catalog verdict, so a caller can keep showing the
    /// catalog's own opinion alongside it.
    var isLocalObservation: Bool { self == .crashed }

    // MARK: Derivation

    /// Resolves what to show. Pure, so the priority order is tested without a
    /// filesystem, a bottle or a running game.
    ///
    /// Order matters and the two interesting choices are:
    ///
    /// `blocked` outranks everything except `native`, because no other signal
    /// helps a player whose anti-cheat will never load under Wine.
    ///
    /// `crashed` outranks `verified` deliberately: a crash here and now is
    /// more actionable than a catalog entry saying it works elsewhere. It is
    /// also the only state that reports a transient event, so it must clear —
    /// see ``clearsCrash(afterCleanExit:)`` — and callers are expected to keep
    /// showing the catalog verdict beside it rather than losing that signal.
    static func resolve(
        confidence: GameConfidence,
        isNative: Bool = false,
        crashedLastRun: Bool = false
    ) -> Health {
        if isNative { return .native }
        if confidence == .blocked { return .blocked }
        if crashedLastRun { return .crashed }
        switch confidence {
        case .verified: return .verified
        case .caveat: return .tweaks
        case .played: return .played
        case .unknown: return .untested
        case .blocked: return .blocked      // handled above; keeps the switch total
        }
    }

    /// Whether a run clears the `crashed` badge.
    ///
    /// A clean exit is an exit code of 0, or a session long enough to be real
    /// play that the user ended themselves — a game quit from its own menu
    /// after an hour is not evidence of a crash, whatever it returns.
    static func clearsCrash(exitCode: Int32?, sessionSeconds: Double) -> Bool {
        if exitCode == 0 { return true }
        return sessionSeconds >= cleanSessionSeconds
    }

    /// A minute of play is the threshold for "it actually ran", matching the
    /// evidence bar `GameConfidence` already uses for `played`.
    static let cleanSessionSeconds: Double = 60
}
