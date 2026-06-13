import Foundation

enum WinetricksError: LocalizedError {
    case notInCatalog
    case scriptNotFound(String)
    case verbFailed(slug: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .notInCatalog:
            "The version catalog has no winetricks entry."
        case .scriptNotFound(let searched):
            "Winetricks is installed but the script wasn't found under \(searched)."
        case .verbFailed(let slug, let detail):
            "Winetricks couldn't install “\(slug)”: \(detail)"
        }
    }
}

/// Owns the winetricks shell script: install/update + verb catalog +
/// per-bottle verb execution. The catalog is parsed once from the
/// installed script and cached.
@MainActor
final class WinetricksManager: ObservableObject {
    static let componentID = "winetricks"

    @Published private(set) var verbs: [WinetricksVerb] = []
    /// Verb slugs currently installing per bottle.
    @Published private(set) var installing: [Bottle.ID: Set<String>] = [:]

    let componentManager: ComponentManager
    let catalog: VersionCatalog

    init(componentManager: ComponentManager, catalog: VersionCatalog) {
        self.componentManager = componentManager
        self.catalog = catalog
        verbs = (try? loadCatalogFromDisk()) ?? []
    }

    var isInstalled: Bool {
        (try? script()) != nil
    }

    /// Path to the executable script inside the installed component.
    func script() throws -> URL {
        guard let root = componentManager.installedDirectory(for: Self.componentID) else {
            throw ComponentError.notInstalled(Self.componentID)
        }
        let scriptURL = root.appending(path: "winetricks")
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
            throw WinetricksError.scriptNotFound(root.path)
        }
        return scriptURL
    }

    /// Downloads + verifies + installs the script (single-file
    /// component, no tar). Refreshes the in-memory verb catalog.
    func ensureInstalled() async throws {
        guard let component = catalog.components[Self.componentID] else {
            throw WinetricksError.notInCatalog
        }
        if let _ = componentManager.installedDirectory(for: Self.componentID, version: component.version) {
            if verbs.isEmpty { verbs = (try? loadCatalogFromDisk()) ?? [] }
            return
        }

        let fm = FileManager.default
        let downloadDest = AppPaths.downloads.appending(
            path: "winetricks-\(component.version)"
        )
        try fm.createDirectory(at: AppPaths.downloads, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: downloadDest) }

        try await DownloadManager.download(from: component.url, to: downloadDest)

        if !component.sha256.isEmpty {
            let expected = component.sha256
            try await Task.detached {
                try ChecksumVerifier.verify(downloadDest, sha256: expected)
            }.value
        }

        let installRoot = AppPaths.components
            .appending(path: Self.componentID, directoryHint: .isDirectory)
            .appending(path: component.version, directoryHint: .isDirectory)
        try fm.createDirectory(at: installRoot, withIntermediateDirectories: true)
        let scriptURL = installRoot.appending(path: "winetricks")
        if fm.fileExists(atPath: scriptURL.path) {
            try fm.removeItem(at: scriptURL)
        }
        try fm.moveItem(at: downloadDest, to: scriptURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        verbs = (try? loadCatalogFromDisk()) ?? []
    }

    /// Runs `winetricks --unattended <slug>` against a bottle's prefix.
    /// On success, the verb is recorded as installed on the bottle.
    func install(
        verb: WinetricksVerb,
        in bottle: Bottle,
        bottleManager: BottleManager,
        wineManager: WineManager
    ) async throws {
        let scriptURL = try script()
        let wine = try wineManager.wineBinary()
        let prefix = bottleManager.prefixDirectory(for: bottle)

        var env = wineManager.environment(forPrefix: prefix)
        // The script wraps `wine` itself; tell it which one to use.
        env["WINE"] = wine.path
        env["WINESERVER"] = wine.deletingLastPathComponent()
            .appending(path: "wineserver").path
        // winetricks shells out to sha256sum/cabextract/etc.; ensure
        // Homebrew paths are visible too.
        let basePath = env["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(basePath)"

        let log = AppPaths.logs.appending(
            path: GameInstaller.logName(bottle.name, "winetricks-\(verb.id)")
        )

        let bottleID = bottle.id
        installing[bottleID, default: []].insert(verb.id)
        defer { installing[bottleID]?.remove(verb.id) }

        let process = try ProcessRunner.start(
            URL(filePath: "/bin/sh"),
            arguments: [scriptURL.path, "--unattended", verb.id],
            environment: env,
            currentDirectory: prefix,
            redirectingOutputTo: log
        )
        let exit = await process.waitForExit()
        guard exit == 0 else {
            throw WinetricksError.verbFailed(
                slug: verb.id,
                detail: "exit code \(exit) — see \(log.lastPathComponent)"
            )
        }

        try bottleManager.setWinetricksVerbInstalled(verb.id, for: bottle.id)
    }

    func isInstalling(_ verbID: String, in bottle: Bottle) -> Bool {
        installing[bottle.id]?.contains(verbID) ?? false
    }

    // MARK: Catalog loading

    private func loadCatalogFromDisk() throws -> [WinetricksVerb] {
        let scriptURL = try script()
        let text = try String(contentsOf: scriptURL, encoding: .utf8)
        return WinetricksCatalog.verbs(fromScript: text)
    }
}
