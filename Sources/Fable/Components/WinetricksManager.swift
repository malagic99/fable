import Foundation

enum WinetricksError: LocalizedError {
    case notInCatalog
    case scriptNotFound(String)
    case verbFailed(slug: String, detail: String)
    case timedOut(slug: String, minutes: Int)

    var errorDescription: String? {
        switch self {
        case .notInCatalog:
            "The version catalog has no winetricks entry."
        case .scriptNotFound(let searched):
            "Winetricks is installed but the script wasn't found under \(searched)."
        case .verbFailed(let slug, let detail):
            "Winetricks couldn't install “\(slug)”: \(detail)"
        case .timedOut(let slug, let minutes):
            "Installing “\(slug)” stalled for over \(minutes) min — likely a slow or dead "
            + "download mirror. Already-fetched files are cached, so retrying usually resumes."
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
        // Make wget fail fast on a stalled mirror instead of hanging on its
        // 15-min default read-timeout (the "stuck on corefonts" symptom) —
        // short timeout + a few retries so it rolls past a dead SourceForge
        // mirror quickly. Cache is the default ~/.cache/winetricks, so any
        // file already fetched is reused.
        env["WGETRC"] = try Self.resilientWgetConfig().path

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

        // Backstop: no single verb should run forever. Steam's client
        // download is legitimately long, so the cap is generous; a true
        // hang (dead mirror surviving wget's own retries) gets killed and
        // surfaced as retriable rather than appearing frozen indefinitely.
        let exit = await Self.waitForExit(process, timeout: Self.installTimeout)
        guard let code = exit else {
            process.terminate()
            throw WinetricksError.timedOut(
                slug: verb.id, minutes: Int(Self.installTimeout / 60)
            )
        }
        guard code == 0 else {
            throw WinetricksError.verbFailed(
                slug: verb.id,
                detail: "exit code \(code) — see \(log.lastPathComponent)"
            )
        }

        try bottleManager.setWinetricksVerbInstalled(verb.id, for: bottle.id)
    }

    /// Upper bound on a single winetricks verb (seconds). Generous so a
    /// legitimate Steam client download isn't cut off, tight enough that a
    /// dead-mirror hang doesn't look permanent.
    static let installTimeout: TimeInterval = 30 * 60

    /// Awaits the process, returning its exit code, or `nil` if `timeout`
    /// seconds elapse first (caller terminates).
    nonisolated static func waitForExit(_ process: LaunchedProcess, timeout: TimeInterval) async -> Int32? {
        await withTaskGroup(of: Int32?.self) { group in
            group.addTask { await process.waitForExit() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Writes (once) a wget config that fails fast on stalled connections so
    /// a flaky download mirror can't hang an install. Returns its path.
    nonisolated static func resilientWgetConfig() throws -> URL {
        let url = AppPaths.components.appending(path: "winetricks-wgetrc")
        let contents = """
        timeout = 45
        tries = 3
        retry_connrefused = on
        waitretry = 5
        """
        if (try? String(contentsOf: url, encoding: .utf8)) != contents {
            try FileManager.default.createDirectory(
                at: AppPaths.components, withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
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
