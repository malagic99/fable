import Foundation

/// Filesystem locations used by Fable, all under
/// ~/Library/Application Support/Fable/.
///
/// Not *everything* Fable persists lives here: the first-run completion marker
/// deliberately does (see OnboardingState), but the settings backing it sit in
/// UserDefaults, which survives deleting this directory. That difference is
/// why a wiped Mac once read back as "already onboarded".
enum AppPaths {
    static var applicationSupport: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Fable", directoryHint: .isDirectory)
    }

    /// Wine prefixes ("bottles"), one subdirectory per bottle.
    static var bottles: URL {
        applicationSupport.appending(path: "Bottles", directoryHint: .isDirectory)
    }

    /// Downloaded runtime components (Wine, DXMT), one subdirectory per component.
    static var components: URL {
        applicationSupport.appending(path: "Components", directoryHint: .isDirectory)
    }

    /// In-progress downloads before checksum verification and extraction.
    static var downloads: URL {
        applicationSupport.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    /// Per-launch Wine output logs (the debugging fallback when a game
    /// won't start).
    static var logs: URL {
        applicationSupport.appending(path: "Logs", directoryHint: .isDirectory)
    }

    /// Cached external compatibility data (anti-cheat DB, ProtonDB) that the
    /// quirk system fetches and reuses offline.
    static var quirkCache: URL {
        applicationSupport.appending(path: "QuirkCache", directoryHint: .isDirectory)
    }

    /// User-imported shareable game recipes (`.fablerecipe` files).
    static var recipes: URL {
        applicationSupport.appending(path: "Recipes", directoryHint: .isDirectory)
    }

    /// Durable snapshot of D3DMetal shader caches, so they survive macOS
    /// purging the volatile darwin cache dir (and can be offloaded externally).
    static var shaderCache: URL {
        applicationSupport.appending(path: "ShaderCache", directoryHint: .isDirectory)
    }

    /// Downloaded cover art, one image per title (fetched at most once).
    static var artwork: URL {
        applicationSupport.appending(path: "Artwork", directoryHint: .isDirectory)
    }

    /// User themes (`.fableskin` files) and their background images.
    static var themes: URL {
        applicationSupport.appending(path: "Themes", directoryHint: .isDirectory)
    }

    static func ensureDirectoriesExist() throws {
        for url in [applicationSupport, bottles, components, downloads, logs] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
