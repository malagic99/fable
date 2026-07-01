import Foundation

/// A DualSense adaptive-trigger effect for one trigger (L2 or R2). Maps to the
/// GCDualSenseAdaptiveTrigger modes. Validated on hardware (USB + Bluetooth).
enum TriggerMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case off, feedback, weapon, vibration
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .feedback: "Feedback"
        case .weapon: "Weapon"
        case .vibration: "Vibration"
        }
    }
}

/// Parameters for one trigger. Which fields matter depends on `mode`:
/// feedback → start+strength; weapon → start+end+strength; vibration →
/// start+amplitude+frequency. All normalized 0…1.
struct TriggerEffect: Codable, Hashable, Sendable {
    var mode: TriggerMode = .off
    var start: Float = 0.2
    var end: Float = 0.7
    var strength: Float = 1.0
    var amplitude: Float = 0.8
    var frequency: Float = 0.5
}

/// Both triggers' effects — a per-bottle default (with optional per-game
/// override). "For this game, R2 is a weapon-break at 35%." Like Steam Input's
/// trigger config: user-set and static, since a Wine game's own DualSense SDK
/// calls never execute to drive it contextually.
struct TriggerProfile: Codable, Hashable, Sendable {
    var left: TriggerEffect = TriggerEffect()
    var right: TriggerEffect = TriggerEffect()

    /// Whether either trigger does anything (drives the "active" indicator and
    /// whether Fable bothers touching the pad at launch).
    var isActive: Bool { left.mode != .off || right.mode != .off }

    static let off = TriggerProfile()

    // MARK: Presets — one-click starting points, tuned to feel reasonable.

    /// R2 a firm weapon-break; L2 light constant tension (aim).
    static let shooter = TriggerProfile(
        left: TriggerEffect(mode: .feedback, start: 0.0, strength: 0.5),
        right: TriggerEffect(mode: .weapon, start: 0.35, end: 0.7, strength: 1.0)
    )
    /// R2 heavy from the start (throttle), L2 firm (brake).
    static let racing = TriggerProfile(
        left: TriggerEffect(mode: .feedback, start: 0.15, strength: 0.9),
        right: TriggerEffect(mode: .feedback, start: 0.1, strength: 0.6)
    )
    /// Both heavy the whole pull — a bow-draw / melee "effortful" feel.
    static let heavy = TriggerProfile(
        left: TriggerEffect(mode: .feedback, start: 0.0, strength: 1.0),
        right: TriggerEffect(mode: .feedback, start: 0.0, strength: 1.0)
    )

    static let presets: [(name: String, profile: TriggerProfile)] = [
        ("Off", .off),
        ("Shooter", .shooter),
        ("Racing", .racing),
        ("Heavy / Bow", .heavy),
    ]
}
