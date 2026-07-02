import Foundation

/// A game that runs natively on macOS — no Wine, no bottle. Imported from the
/// native Steam client or added as a plain `.app` (App Store, web, anywhere).
/// Sits in the library beside the Wine games so Fable is the one launcher.
struct NativeGame: Identifiable, Codable, Hashable, Sendable {
    enum Source: Codable, Hashable, Sendable {
        /// Launched through the native Steam client (`steam://rungameid/`).
        case steam(appID: Int)
        /// A .app bundle launched directly.
        case app(path: String)
    }

    var id: UUID
    var name: String
    var source: Source

    init(id: UUID = UUID(), name: String, source: Source) {
        self.id = id
        self.name = name
        self.source = source
    }

    /// The Steam appid, when this is a native Steam game — feeds cover art
    /// directly (no name search needed).
    var steamAppID: Int? {
        if case .steam(let appID) = source { return appID }
        return nil
    }

    /// The app bundle path, when this is a plain .app.
    var appPath: String? {
        if case .app(let path) = source { return path }
        return nil
    }

    var sourceLabel: String {
        switch source {
        case .steam: "Native Steam"
        case .app: "Mac app"
        }
    }
}
