import Foundation

enum WineError: LocalizedError {
    case notInCatalog
    case binaryNotFound(searched: String)
    case prefixCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInCatalog:
            "The version catalog has no Wine entry."
        case .binaryNotFound(let searched):
            "Wine is installed but no wine binary was found under \(searched)."
        case .prefixCreationFailed(let detail):
            "Couldn't initialize the Wine prefix: \(detail)"
        }
    }
}

/// Owns the Wine installation and prefix lifecycle.
@MainActor
final class WineManager: ObservableObject {
    let componentManager: ComponentManager
    let catalog: VersionCatalog

    static let componentID = "wine"

    init(componentManager: ComponentManager, catalog: VersionCatalog) {
        self.componentManager = componentManager
        self.catalog = catalog
    }

    var isWineInstalled: Bool {
        (try? wineBinary()) != nil
    }

    /// Downloads and installs Wine if missing. Progress is observable
    /// through componentManager.states["wine"].
    func ensureWineInstalled() async throws {
        guard let wine = catalog.wine else { throw WineError.notInCatalog }
        try await componentManager.install(id: Self.componentID, component: wine)
    }

    /// Locates the wine binary inside the installed component
    /// (e.g. Wine Stable.app/Contents/Resources/wine/bin/wine64).
    func wineBinary() throws -> URL {
        guard let root = componentManager.installedDirectory(for: Self.componentID) else {
            throw ComponentError.notInstalled(Self.componentID)
        }
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isExecutableKey]) {
            for case let url as URL in enumerator {
                let path = url.path
                if path.hasSuffix("/bin/wine64") || path.hasSuffix("/bin/wine") {
                    return url
                }
            }
        }
        throw WineError.binaryNotFound(searched: root.path)
    }

    /// wineserver lives next to wine in the same bin directory.
    func wineserverBinary() throws -> URL {
        try wineBinary().deletingLastPathComponent().appending(path: "wineserver")
    }

    /// `wineserver -k` against a prefix: hard-kills every process in
    /// the prefix's session. The escape hatch for hung games.
    func forceKillPrefix(_ prefix: URL) async throws {
        _ = try await ProcessRunner.run(
            try wineserverBinary(),
            arguments: ["-k"],
            environment: environment(forPrefix: prefix)
        )
    }

    /// The base Wine environment for a prefix — the prefix path plus Fable's
    /// always-on quirk fixes. Every fix is documented in one place: `WineEnv`.
    func environment(forPrefix prefix: URL) -> [String: String] {
        WineEnv.base(prefix: prefix)
    }

    /// Launches a Wine GUI tool (winecfg, regedit, taskmgr, …) in a
    /// prefix without waiting for it.
    @discardableResult
    func openTool(_ tool: String, inPrefix prefix: URL) throws -> LaunchedProcess {
        let env = WineEnv.withDiagnosticDebug(environment(forPrefix: prefix))
        return try ProcessRunner.start(
            try wineBinary(),
            arguments: [tool],
            environment: env,
            redirectingOutputTo: AppPaths.logs.appending(path: GameInstaller.logName("tool", tool))
        )
    }

    /// Sets winemac.drv Retina mode (and matching DPI) for a prefix.
    ///
    /// Macs ship Retina (2×) panels; by default winemac.drv backs each Wine
    /// window with a 1× surface, so an app renders at half pixel density and
    /// macOS upscales the whole window — soft, visibly pixelated text and
    /// images (most obvious in Steam's CEF login). `RetinaMode=y` gives the
    /// window a native-resolution backing store; bumping `LogPixels` to 192
    /// (0xC0) doubles Windows' DPI scaling so the UI lands at the right
    /// physical size instead of being crisp-but-tiny. This is the same pair
    /// CrossOver sets behind its "Retina mode" toggle.
    ///
    /// The flip side: many games aren't HiDPI-aware (SDL/GL titles like
    /// LÖVE-based Balatro) and render into a corner with input mapped to the
    /// full window when Retina is on — so this is a per-bottle choice, off by
    /// default. `enabled == false` writes `n`/96 to revert cleanly. Takes
    /// effect when the prefix's processes next cold-start. Idempotent.
    func setRetinaMode(_ enabled: Bool, at prefix: URL) async throws {
        let wine = try wineBinary()
        let env = environment(forPrefix: prefix)
        _ = try await ProcessRunner.run(
            wine,
            arguments: ["reg", "add", #"HKCU\Software\Wine\Mac Driver"#,
                        "/v", "RetinaMode", "/t", "REG_SZ", "/d", enabled ? "y" : "n", "/f"],
            environment: env
        )
        _ = try await ProcessRunner.run(
            wine,
            arguments: ["reg", "add", #"HKCU\Control Panel\Desktop"#,
                        "/v", "LogPixels", "/t", "REG_DWORD", "/d", enabled ? "192" : "96", "/f"],
            environment: env
        )
    }

    /// The prefix's current winemac.drv Retina mode, read straight from
    /// user.reg. nil when the key isn't present. Exposed for testing.
    nonisolated static func currentRetinaMode(at prefix: URL) -> Bool? {
        guard let reg = try? String(contentsOf: prefix.appending(path: "user.reg"), encoding: .utf8),
              let line = reg.split(separator: "\n").first(where: { $0.contains(#""RetinaMode"="#) })
        else { return nil }
        return line.contains(#""y""#)
    }

    /// Makes the prefix's Retina mode match `enabled`, writing only when it
    /// has drifted — so the bottle's saved setting stays authoritative if the
    /// registry was ever changed out of band. Cheap no-op when already in sync.
    func reconcileRetinaMode(_ enabled: Bool, at prefix: URL) async {
        guard Self.currentRetinaMode(at: prefix) != enabled else { return }
        try? await setRetinaMode(enabled, at: prefix)
    }

    /// Initializes a fresh Wine prefix and pins its Windows version.
    func createPrefix(at prefix: URL, windowsVersion: WindowsVersion) async throws {
        let wine = try wineBinary()
        let env = environment(forPrefix: prefix)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)

        let boot = try await ProcessRunner.run(wine, arguments: ["wineboot", "--init"], environment: env)
        guard boot.succeeded else {
            throw WineError.prefixCreationFailed(boot.standardError.isEmpty ? "wineboot exited with \(boot.exitCode)" : boot.standardError)
        }

        let setVersion = try await ProcessRunner.run(
            wine,
            arguments: ["winecfg", "-v", windowsVersion.rawValue],
            environment: env
        )
        guard setVersion.succeeded else {
            throw WineError.prefixCreationFailed("couldn't set Windows version: \(setVersion.standardError)")
        }

        // Default Retina OFF: it crisps launcher/CEF UI but breaks many
        // non-HiDPI games. A per-bottle toggle opts in (see Bottle.retinaMode).
        try await setRetinaMode(false, at: prefix)

        // Wait for wineserver to finish flushing the new prefix.
        _ = try await ProcessRunner.run(try wineserverBinary(), arguments: ["-w"], environment: env)

        // Sanity check that the prefix actually materialized.
        let driveC = prefix.appending(path: "drive_c")
        guard FileManager.default.fileExists(atPath: driveC.path) else {
            throw WineError.prefixCreationFailed("prefix has no drive_c after wineboot")
        }
    }
}
