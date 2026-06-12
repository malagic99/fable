import Foundation

/// Filesystem locations used by Fable. Everything lives under
/// ~/Library/Application Support/Fable/.
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

    static func ensureDirectoriesExist() throws {
        for url in [applicationSupport, bottles, components, downloads] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
