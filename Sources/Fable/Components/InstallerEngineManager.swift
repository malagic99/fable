import Foundation

/// The Wine that runs 32-bit Windows installers: Sikarugir's build of
/// CrossOver 24's published source (Wine 9.0), downloaded by Fable.
///
/// Why a separate engine just for installers — measured on 2026-11-11 with
/// five InstallShield installers (versions 5, 6, 6.3–8, InstallScript MSI,
/// Basic MSI), each on a fresh prefix:
/// - this engine installed 5 of 5;
/// - Fable's main Wine 11.10 installed 2 of 5 — InstallShield's `IKernel.exe`
///   dies in a storm of `dispatch_user_callback ignoring exception c0000005`
///   (a 32-bit exception-handling regression in Wine 11 under Rosetta);
/// - the Wine 7.7 runtimes Fable used to borrow (GPTK, Whisky, Heroic)
///   finished 0 of 5 unattended.
///
/// The tarball carries no support dylibs (libinotify, freetype, gnutls), so
/// they come from Sikarugir's template — the same pinned download the
/// Sikarugir 11 backend uses — and are copied into the engine's `lib/`.
@MainActor
final class InstallerEngineManager: ObservableObject {
    let componentManager: ComponentManager
    let catalog: VersionCatalog

    nonisolated static let componentID = "installer-engine"
    nonisolated static let runtimeName = "Fable's installer engine (CrossOver 24)"
    /// Written once the support libraries are in place.
    nonisolated static let assembledMarker = ".fable-assembled"

    @Published private(set) var isInstalled = false
    /// The install in flight, shared by every caller.
    private var installTask: Task<Void, Error>?

    init(componentManager: ComponentManager, catalog: VersionCatalog) {
        self.componentManager = componentManager
        self.catalog = catalog
        refresh()
    }

    func refresh() {
        isInstalled = Self.installedRuntime(componentsDirectory: componentManager.componentsDirectory) != nil
    }

    /// Downloads (if needed) and assembles the engine. Idempotent.
    func ensureInstalled() async throws {
        if let installTask { return try await installTask.value }
        let task = Task { try await self.install() }
        installTask = task
        defer { installTask = nil }
        try await task.value
    }

    private func install() async throws {
        guard let engine = catalog.components[Self.componentID] else {
            throw Sikarugir11Error.notInCatalog(Self.componentID)
        }
        guard let template = catalog.components[Sikarugir11Manager.templateComponentID] else {
            throw Sikarugir11Error.notInCatalog(Sikarugir11Manager.templateComponentID)
        }
        let root = try await componentManager.install(id: Self.componentID, component: engine)
        if !Self.isAssembled(root) {
            let templateRoot = try await componentManager.install(
                id: Sikarugir11Manager.templateComponentID, component: template)
            guard let app = Sikarugir11Manager.templateApp(in: templateRoot) else {
                throw Sikarugir11Error.rendererMissing(templateRoot.path)
            }
            try await Self.assemble(engineRoot: root, templateApp: app)
            try Data(template.version.utf8).write(to: root.appending(path: Self.assembledMarker))
        }
        refresh()
    }

    nonisolated static func isAssembled(_ engineRoot: URL) -> Bool {
        FileManager.default.fileExists(atPath: engineRoot.appending(path: assembledMarker).path)
    }

    /// Copies the template's support dylibs into the engine and makes sure the
    /// wineserver can find them when Fable runs it bare (`-w`, `-k`).
    nonisolated static func assemble(engineRoot: URL, templateApp: URL) async throws {
        let bundle = engineRoot.appending(path: "wswine.bundle", directoryHint: .isDirectory)
        let lib = bundle.appending(path: "lib", directoryHint: .isDirectory)
        let frameworks = templateApp.appending(path: "Contents/Frameworks", directoryHint: .isDirectory)
        let fm = FileManager.default
        let dylibs = ((try? fm.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "dylib" }
        guard dylibs.contains(where: { $0.lastPathComponent.hasPrefix("libinotify") }) else {
            throw Sikarugir11Error.rendererMissing(frameworks.path)
        }
        for item in dylibs {
            try Sikarugir11Manager.replaceItem(at: lib.appending(path: item.lastPathComponent), with: item)
        }

        let wineserver = bundle.appending(path: "bin/wineserver")
        try Sikarugir11Manager.addLibraryRpath(to: wineserver)
        let verify = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/codesign"), arguments: ["--verify", wineserver.path])
        if !verify.succeeded {
            try await Sikarugir11Manager.checked("/usr/bin/codesign", ["--force", "--sign", "-", wineserver.path])
        }
        _ = try? await ProcessRunner.run(
            URL(filePath: "/usr/bin/xattr"), arguments: ["-dr", "com.apple.quarantine", engineRoot.path])
    }

    // MARK: Runtime

    /// The assembled engine as a compatibility runtime, or nil when it isn't
    /// installed. Nonisolated and path-based so discovery can call it.
    nonisolated static func installedRuntime(componentsDirectory: URL) -> CompatibilityRuntime? {
        let fm = FileManager.default
        let dir = componentsDirectory.appending(path: componentID, directoryHint: .isDirectory)
        let versions = ((try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for root in versions.reversed() where isAssembled(root) {
            let bundle = root.appending(path: "wswine.bundle", directoryHint: .isDirectory)
            let wine = bundle.appending(path: "bin/wine")
            guard fm.isExecutableFile(atPath: wine.path) else { continue }
            return CompatibilityRuntime(
                name: runtimeName, wineBinary: wine, environment: launchEnvironment(bundleRoot: bundle))
        }
        return nil
    }

    /// What the engine needs beyond the prefix: its own `lib/` for the fonts
    /// and TLS libraries Wine loads by name.
    nonisolated static func launchEnvironment(bundleRoot: URL) -> [String: String] {
        ["DYLD_FALLBACK_LIBRARY_PATH": [
            bundleRoot.appending(path: "lib").path, "/usr/lib", "/usr/libexec", "/usr/lib/system",
        ].joined(separator: ":")]
    }
}
