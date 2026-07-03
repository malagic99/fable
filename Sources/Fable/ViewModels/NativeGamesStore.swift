import AppKit

/// Owns the native macOS games in the library: persistence, import from the
/// native Steam client, plain .app adds, launching, and (for .apps) a live
/// running check. No Wine anywhere in this file — that's the point.
@MainActor
final class NativeGamesStore: ObservableObject {
    @Published private(set) var games: [NativeGame] = []

    private let fileURL: URL

    init(fileURL: URL = AppPaths.applicationSupport.appending(path: "native-games.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([NativeGame].self, from: data) {
            games = loaded
        }
    }

    // MARK: Import

    /// Installed games in the native Steam client not yet imported.
    /// Steam's own tooling (redists, SteamVR, controller configs) is filtered,
    /// as are stale manifests whose game files are gone from disk — Steam
    /// fails those launches silently, so offering them would be a lie.
    func availableNativeSteamGames() -> [(appID: Int, name: String)] {
        guard let root = SteamAppManifest.nativeSteamRoot() else { return [] }
        let imported = Set(games.compactMap(\.steamAppID))
        return SteamAppManifest.installedApps(steamRoot: root)
            .filter { app in
                !imported.contains(app.appID) && !Self.isSteamTooling(app.name)
                    && SteamAppManifest.hasGameFiles(installDir: app.installDir, steamRoot: root)
            }
            .map { (appID: $0.appID, name: $0.name) }
    }

    func importNativeSteamGames(_ apps: [(appID: Int, name: String)]) {
        for app in apps where !games.contains(where: { $0.steamAppID == app.appID }) {
            games.append(NativeGame(name: app.name, source: .steam(appID: app.appID)))
        }
        sortAndSave()
    }

    /// Adds a plain .app (App Store, web, anywhere). Name from the bundle.
    func addApp(at url: URL) {
        let path = url.path
        guard !games.contains(where: { $0.appPath == path }) else { return }
        let name = (url.deletingPathExtension().lastPathComponent)
        games.append(NativeGame(name: name, source: .app(path: path)))
        sortAndSave()
    }

    func remove(_ game: NativeGame) {
        games.removeAll { $0.id == game.id }
        sortAndSave()
    }

    // MARK: Launch + state

    /// Launches natively: .app via LaunchServices, Steam games through the
    /// native client's URL scheme (Steam handles login, DRM, cloud saves).
    func launch(_ game: NativeGame) {
        switch game.source {
        case .app(let path):
            NSWorkspace.shared.openApplication(
                at: URL(filePath: path),
                configuration: NSWorkspace.OpenConfiguration()
            )
        case .steam(let appID):
            if let url = URL(string: "steam://rungameid/\(appID)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Live running check for .app games (Steam-launched natives are the
    /// client's to track — honestly unknown, so false).
    func isRunning(_ game: NativeGame) -> Bool {
        guard let path = game.appPath else { return false }
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.path == path
        }
    }

    /// Filtered, sorted view for the library surfaces.
    func entries(query: String = "") -> [NativeGame] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return games }
        return games.filter { $0.name.lowercased().contains(needle) }
    }

    // MARK: Internals

    /// Steam's non-game entries that would pollute the import list.
    nonisolated static func isSteamTooling(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("redistributable") || lower.contains("steamworks common")
            || lower.hasPrefix("steamvr") || lower.contains("controller config")
            || lower.contains("proton") || lower.contains("steam linux runtime")
    }

    private func sortAndSave() {
        games.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(games) {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
