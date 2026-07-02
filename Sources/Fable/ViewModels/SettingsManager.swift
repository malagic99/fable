import Foundation

/// Which face Fable wears. Classic is the utility (bottles + settings first);
/// Gamer is the cover wall (games first, tools one level down). Chosen on
/// first launch, switchable in Settings → Interface.
enum InterfaceStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic
    case gamer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: "Classic"
        case .gamer: "Gamer"
        }
    }

    var blurb: String {
        switch self {
        case .classic: "Bottles and tools up front — the workshop."
        case .gamer: "Your games as a cover wall — play first, tools one click away."
        }
    }
}

/// Global app configuration, persisted to Application Support/config.json.
struct AppSettings: Codable, Equatable, Sendable {
    /// Defaults applied to newly created bottles.
    var defaultWindowsVersion: WindowsVersion = .win10
    var defaultDXMTEnabled: Bool = false
    var defaultDXMTConfig: DXMTConfig = DXMTConfig()
    /// When off (default), bottles show a streamlined click-and-play view;
    /// when on, the full backend/performance/storage/troubleshooting panels.
    var advancedMode: Bool = false

    /// Opt-in: look up per-game compatibility online (ProtonDB). Off by default
    /// because a lookup sends the game's Steam appid to a third party. The
    /// offline anti-cheat database always works regardless.
    var onlineCompatibilityLookups: Bool = false

    /// The app's face — classic utility or games-first cover wall. Picked in
    /// onboarding; existing configs decode to .classic (no surprise change).
    var interfaceStyle: InterfaceStyle = .classic

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultWindowsVersion = try container
            .decodeIfPresent(WindowsVersion.self, forKey: .defaultWindowsVersion) ?? .win10
        defaultDXMTEnabled = try container
            .decodeIfPresent(Bool.self, forKey: .defaultDXMTEnabled) ?? false
        defaultDXMTConfig = try container
            .decodeIfPresent(DXMTConfig.self, forKey: .defaultDXMTConfig) ?? DXMTConfig()
        advancedMode = try container
            .decodeIfPresent(Bool.self, forKey: .advancedMode) ?? false
        onlineCompatibilityLookups = try container
            .decodeIfPresent(Bool.self, forKey: .onlineCompatibilityLookups) ?? false
        interfaceStyle = try container
            .decodeIfPresent(InterfaceStyle.self, forKey: .interfaceStyle) ?? .classic
    }
}

/// Owns AppSettings: loads at launch, saves on every change.
@MainActor
final class SettingsManager: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    let configURL: URL

    init(configURL: URL = AppPaths.applicationSupport.appending(path: "config.json")) {
        self.configURL = configURL
        if let data = try? Data(contentsOf: configURL),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loaded
        } else {
            // Missing or corrupted config: start fresh with defaults.
            settings = AppSettings()
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(settings).write(to: configURL, options: .atomic)
        } catch {
            NSLog("Fable: failed to save settings: \(error)")
        }
    }
}
