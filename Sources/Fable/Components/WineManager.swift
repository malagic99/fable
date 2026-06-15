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

    func environment(forPrefix prefix: URL) -> [String: String] {
        [
            "WINEPREFIX": prefix.path,
            "WINEDEBUG": "-all",
            // Skip Mono/Gecko installer dialogs — prefix creation must
            // never block on UI. Games that need .NET get it via the
            // bottle later.
            "WINEDLLOVERRIDES": "mscoree,mshtml=",
            // Make Rosetta 2 advertise AVX/AVX2/FMA/BMI2 to the
            // translated x86 process (and its children — i.e. the game).
            // Default Rosetta hides these, so any game whose CPU check
            // requires AVX aborts with int3 before it ever renders, for
            // no visible reason. macOS 15+/26 Rosetta supports them
            // behind this opt-in. No-op on native-arm64 Wine. Verified
            // 2026-06-15: unset → AVX=0; =1 → AVX=1,AVX2=1,FMA=1,BMI2=1.
            "ROSETTA_ADVERTISE_AVX": "1",
        ]
    }

    /// Launches a Wine GUI tool (winecfg, regedit, taskmgr, …) in a
    /// prefix without waiting for it.
    @discardableResult
    func openTool(_ tool: String, inPrefix prefix: URL) throws -> LaunchedProcess {
        var env = environment(forPrefix: prefix)
        env["WINEDEBUG"] = "fixme-all"
        return try ProcessRunner.start(
            try wineBinary(),
            arguments: [tool],
            environment: env,
            redirectingOutputTo: AppPaths.logs.appending(path: GameInstaller.logName("tool", tool))
        )
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

        // Wait for wineserver to finish flushing the new prefix.
        _ = try await ProcessRunner.run(try wineserverBinary(), arguments: ["-w"], environment: env)

        // Sanity check that the prefix actually materialized.
        let driveC = prefix.appending(path: "drive_c")
        guard FileManager.default.fileExists(atPath: driveC.path) else {
            throw WineError.prefixCreationFailed("prefix has no drive_c after wineboot")
        }
    }
}
