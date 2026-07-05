import Foundation

/// The app's display language. `.system` follows macOS; a fixed choice
/// overrides it via the standard `AppleLanguages` mechanism — which takes
/// effect on the next launch (Foundation reads it at process start).
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case spanish = "es"
    case portuguese = "pt"

    var id: String { rawValue }

    /// Each language names itself — recognizable even when the app is
    /// currently showing a language you don't read.
    var displayName: String {
        switch self {
        case .system: L10n.string("language.system")
        case .english: "English"
        case .spanish: "Español"
        case .portuguese: "Português"
        }
    }

    /// Writes (or clears) the launch-language override. Effective next launch.
    func apply(to defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }
}
