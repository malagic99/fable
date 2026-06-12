import Foundation

/// A CrossOver-lineage Wine (wine32on64, predating WoW64) used to run
/// 32-bit installers that crash mainline Wine's WoW64 layer. Fable
/// never downloads one — CodeWeavers stopped publishing redistributable
/// sources — but several apps ship one we can discover locally.
struct CompatibilityRuntime: Sendable {
    let name: String
    let wineBinary: URL

    var wineserverBinary: URL {
        wineBinary.deletingLastPathComponent().appending(path: "wineserver")
    }

    /// Search known locations, preferring Fable's own (future GPTK
    /// import) over other apps' copies.
    static func discover(componentsDirectory: URL = AppPaths.components) -> CompatibilityRuntime? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        var candidates: [(String, URL)] = []

        // Fable's own imported GPTK component (Day 11 import flow).
        candidates.append((
            "Game Porting Toolkit",
            componentsDirectory.appending(path: "gptk", directoryHint: .isDirectory)
        ))
        // Heroic's GPTK toolkit.
        candidates.append((
            "Heroic Game Porting Toolkit",
            home.appending(path: "Library/Application Support/heroic/tools/game-porting-toolkit")
        ))
        // Whisky's WhiskyWine (GPTK-based).
        candidates.append((
            "WhiskyWine",
            home.appending(path: "Library/Application Support/com.isaacmarovitz.Whisky/Libraries")
        ))
        // CrossOver itself.
        candidates.append((
            "CrossOver",
            URL(filePath: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver")
        ))

        for (name, root) in candidates {
            if let wine = findWineBinary(under: root) {
                return CompatibilityRuntime(name: name, wineBinary: wine)
            }
        }
        return nil
    }

    /// Finds bin/wine64 (or bin/wine) beneath `root`, a few levels deep.
    private static func findWineBinary(under root: URL) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return nil }
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isExecutableKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            // Bail out of deep game/prefix trees quickly.
            if enumerator.level > 8 { enumerator.skipDescendants(); continue }
            let path = url.path
            if (path.hasSuffix("/bin/wine64") || path.hasSuffix("/bin/wine")),
               fm.isExecutableFile(atPath: path) {
                return url
            }
        }
        return nil
    }
}
