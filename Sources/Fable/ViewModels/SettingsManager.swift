import Foundation

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
