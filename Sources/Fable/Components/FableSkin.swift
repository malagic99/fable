import SwiftUI

/// App appearance, independent of theme (a theme *suggests* one on apply).
enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: L10n.string("appearance.system")
        case .light: L10n.string("appearance.light")
        case .dark: L10n.string("appearance.dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// A Fable theme ("skin"): identity gradient, accent, window wash, optional
/// background image — shareable as a `.fableskin` file. Built-ins ship in
/// `FableSkin.builtIns`; user themes live in Application Support/Themes.
struct FableSkin: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    /// Applied to the appearance setting when the theme is selected.
    var suggestedAppearance: AppAppearance?
    /// Accent for controls; nil keeps the system accent.
    var accentHex: String?
    /// The identity gradient (brand mark, fallback covers).
    var gradientStartHex: String
    var gradientEndHex: String
    /// A wash laid over the window background; nil = none.
    var windowTintHex: String?
    var windowTintOpacity: Double = 0.35
    /// Filename of a background image inside `AppPaths.themes/images`.
    var backgroundImageFile: String?

    var accent: Color? { accentHex.flatMap(Color.init(hex:)) }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: gradientStartHex) ?? .purple,
                     Color(hex: gradientEndHex) ?? .indigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var windowTint: Color? { windowTintHex.flatMap(Color.init(hex:)) }

    // MARK: Built-ins

    /// Fable as shipped: system appearance, the wineglass purple→indigo.
    static let standard = FableSkin(
        id: "default", name: "Fable",
        suggestedAppearance: .system,
        accentHex: nil,
        gradientStartHex: "#AF52DE", gradientEndHex: "#5856D6",
        windowTintHex: nil
    )

    /// Deep-night blues on near-black.
    static let midnight = FableSkin(
        id: "midnight", name: "Midnight",
        suggestedAppearance: .dark,
        accentHex: "#4F7BF7",
        gradientStartHex: "#0EA5E9", gradientEndHex: "#6366F1",
        windowTintHex: "#050810", windowTintOpacity: 0.55
    )

    /// The 2004 Steam skin: olive, khaki, and that gold-green.
    static let ogSteam = FableSkin(
        id: "og-steam", name: "OG Steam",
        suggestedAppearance: .dark,
        accentHex: "#C4B550",
        gradientStartHex: "#8A9A5B", gradientEndHex: "#4C5844",
        windowTintHex: "#3F4637", windowTintOpacity: 0.5
    )

    /// Pure pitch black for late-night sessions — the window wash is near-opaque
    /// #000000, so on an OLED/HDR panel the background pixels switch fully off
    /// (true black, no backlight glow, less battery). A calm blue accent and a
    /// dim brand gradient keep the light emission low and easy on the eyes.
    static let pitchBlack = FableSkin(
        id: "pitch-black", name: "Pitch Black",
        suggestedAppearance: .dark,
        accentHex: "#6E9BFF",
        gradientStartHex: "#2A2A3D", gradientEndHex: "#0C0C14",
        windowTintHex: "#000000", windowTintOpacity: 0.98
    )

    static let builtIns: [FableSkin] = [.standard, .midnight, .pitchBlack, .ogSteam]
}

/// The `.fableskin` file: a skin plus its background image (embedded so a
/// theme travels as one file) and a schema version for future-proof imports.
struct FableSkinDocument: Codable {
    static let currentSchema = 1
    var schemaVersion: Int = FableSkinDocument.currentSchema
    var skin: FableSkin
    /// Base64 of the background image, when the skin carries one.
    var backgroundImageData: Data?
}

extension Color {
    /// #RRGGBB (leading # optional). nil for anything malformed.
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
