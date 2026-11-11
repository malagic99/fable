import Foundation

/// The Wine that runs 32-bit installers, which Fable's main Wine 11 handles
/// badly under Rosetta (see ``InstallerEngineManager`` for the measurements).
///
/// First choice is Fable's own installer engine. The rest are fallbacks for
/// when it isn't downloaded: CrossOver-lineage Wines other apps left on disk.
struct CompatibilityRuntime: Sendable {
    let name: String
    let wineBinary: URL
    /// Variables this runtime needs on top of the prefix environment — also
    /// when its wineserver is run on its own.
    var environment: [String: String] = [:]

    var wineserverBinary: URL {
        wineBinary.deletingLastPathComponent().appending(path: "wineserver")
    }

    /// Finds the runtime for 32-bit installers.
    ///
    /// Order matters. Fable's installer engine first: it's the one that was
    /// measured, and Fable controls its version. Then an installed CrossOver
    /// (its proprietary patches handle custom unpackers like ISDone best),
    /// then Fable's own GPTK component, and only then Wines borrowed from
    /// other apps. Those used to come first, which is how a leftover Whisky
    /// library (Wine 7.7, unmaintained) ended up running installers on a Mac
    /// that had Fable's own runtime — and left one orphaned overnight.
    static func discover(
        componentsDirectory: URL = AppPaths.components,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        applications: URL = URL(filePath: "/Applications")
    ) -> CompatibilityRuntime? {
        if let engine = InstallerEngineManager.installedRuntime(componentsDirectory: componentsDirectory) {
            return engine
        }

        var candidates: [(String, URL)] = []

        // CrossOver — has the WoW64 stack patches the others lack.
        candidates.append((
            "CrossOver",
            applications.appending(path: "CrossOver.app/Contents/SharedSupport/CrossOver")
        ))
        // Fable's own imported GPTK component.
        candidates.append((
            "Game Porting Toolkit",
            componentsDirectory.appending(path: "gptk", directoryHint: .isDirectory)
        ))
        // Heroic's GPTK toolkit.
        candidates.append((
            "Heroic Game Porting Toolkit",
            home.appending(path: "Library/Application Support/heroic/tools/game-porting-toolkit")
        ))
        // Whisky's WhiskyWine (CrossOver-derived, no longer maintained).
        candidates.append((
            "WhiskyWine",
            home.appending(path: "Library/Application Support/com.isaacmarovitz.Whisky/Libraries")
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
