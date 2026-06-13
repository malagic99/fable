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

    /// Search known locations for a Wine with macOS-specific WoW64
    /// patches — the prerequisite for running 32-bit custom-packed
    /// installers (ISDone, FreeArc) that crash stock Wine + Apple GPTK
    /// at `err:seh:NtRaiseException Exception frame is not in stack limits`.
    ///
    /// Order matters: CrossOver's proprietary patches handle this
    /// installer class better than any open-source Wine on macOS, so
    /// it goes first when present. Apple GPTK (wine 7.7 base, no
    /// CrossOver patches) is the fallback — better than nothing for
    /// some 32-bit installers, useless for the WoW64-crashers.
    static func discover(componentsDirectory: URL = AppPaths.components) -> CompatibilityRuntime? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        var candidates: [(String, URL)] = []

        // CrossOver — has the WoW64 stack patches the others lack.
        candidates.append((
            "CrossOver",
            URL(filePath: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver")
        ))
        // Whisky's WhiskyWine (CrossOver-derived).
        candidates.append((
            "WhiskyWine",
            home.appending(path: "Library/Application Support/com.isaacmarovitz.Whisky/Libraries")
        ))
        // Heroic's GPTK toolkit.
        candidates.append((
            "Heroic Game Porting Toolkit",
            home.appending(path: "Library/Application Support/heroic/tools/game-porting-toolkit")
        ))
        // Fable's own imported GPTK component.
        candidates.append((
            "Game Porting Toolkit",
            componentsDirectory.appending(path: "gptk", directoryHint: .isDirectory)
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
