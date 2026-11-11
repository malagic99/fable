import Foundation

enum Sikarugir11Error: LocalizedError {
    case notInCatalog(String)
    case rendererMissing(String)
    case binaryNotFound(String)
    case toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInCatalog(let id):
            "The version catalog has no \(id) entry."
        case .rendererMissing(let path):
            "Sikarugir's template downloaded, but its D3DMetal renderer wasn't found under \(path)."
        case .binaryNotFound(let path):
            "Sikarugir's Wine 11 engine is installed, but no wine binary was found under \(path)."
        case .toolFailed(let detail):
            "Setting up Sikarugir's Wine 11 engine needs Apple's command line tools (xcode-select --install): \(detail)"
        }
    }
}

/// Sikarugir's Wine 11 engine paired with the D3DMetal renderer built for it.
///
/// Wine 11 matters because newer Denuvo builds crash on Wine 10 at their
/// first anti-tamper check (a null read right after a direct
/// `NtQuerySystemInformation` syscall), and pass on Wine 11 — Ace Combat 8,
/// Nov 2026. The Wine 10 path (``SikarugirManager``) stays as it is: bottles
/// opt in per backend, because a prefix that has run Wine 11 is upgraded, and
/// the native Steam bridge's builtin is built for Wine 10.
///
/// Unlike the Wine 10 path, nothing comes from the user's Sikarugir install:
/// the engine and the template that carries the renderer are downloaded from
/// Sikarugir's own GitHub releases, pinned by SHA-256 in versions.json, the
/// same way Sikarugir itself fetches them. The template matters because a
/// renderer is tied to one Wine generation — Wine 11 dropped the
/// `__wine_unix_call` export the 1.0.10 renderer imports, so pairing the old
/// renderer with this engine fails at `dxgi.dll` load.
///
/// Three things this engine needs that took a day to find (see
/// docs/wine-quirks.md):
/// - `SikarugirAppWine11` in the environment. Its ntdll checks for the
///   variable and calls `exit(1)` without it, silently, in every Windows
///   process after the first — so `wineboot` and every child die.
/// - The renderer's six host-side `.so` files are symlinks to one
///   `libd3dshared.dylib`. Copied as separate files they load as separate
///   images with separate D3DMetal state, and D3D12 calls through a null
///   pointer. ``overlay(renderer:intoLib:)`` keeps them links.
/// - GStreamer from the template on the library and plugin paths, or video
///   decoding has no H.264 and a game crashes on its first movie.
@MainActor
final class Sikarugir11Manager: ObservableObject {
    let componentManager: ComponentManager
    let catalog: VersionCatalog

    /// The engine, extracted and then assembled in place.
    nonisolated static let engineComponentID = "sikarugir11"
    /// Sikarugir's wrapper template — only its renderer and dylibs are used.
    nonisolated static let templateComponentID = "sikarugir-template"

    /// D3D DLLs the renderer provides as builtins. `d3d12core` is new in this
    /// renderer: games that ship Microsoft's Agility SDK `D3D12Core.dll` must
    /// get D3DMetal's instead.
    ///
    /// Forced through the prefix registry, not `WINEDLLOVERRIDES` as on the
    /// Wine 10 path: Wine reads the environment before any per-program
    /// registry key, and every process Steam starts inherits Steam's
    /// environment — so an environment override would also reach Steam's web
    /// helper, which has to be kept off D3DMetal (see
    /// ``registryCommands``).
    nonisolated static let builtinDLLs = ["d3d11", "d3d12", "d3d12core", "dxgi", "nvapi64"]

    /// The marker written once an engine has been assembled with a template.
    nonisolated static let assembledMarker = ".fable-assembled"

    @Published private(set) var isInstalled = false

    /// The install in flight, shared by every caller — picking the backend
    /// twice, or pressing Play while it downloads, must not run two downloads
    /// into one archive and two assemblies over one tree.
    private var installTask: Task<Void, Error>?

    init(componentManager: ComponentManager, catalog: VersionCatalog) {
        self.componentManager = componentManager
        self.catalog = catalog
        refresh()
    }

    func refresh() {
        isInstalled = (try? wineBinary()) != nil
    }

    // MARK: Install

    /// Downloads (if needed) and assembles the engine. Idempotent: a finished
    /// engine is left alone.
    func ensureInstalled() async throws {
        if let installTask { return try await installTask.value }
        let task = Task { try await self.install() }
        installTask = task
        defer { installTask = nil }
        try await task.value
    }

    private func install() async throws {
        guard let engine = catalog.components[Self.engineComponentID] else {
            throw Sikarugir11Error.notInCatalog(Self.engineComponentID)
        }
        guard let template = catalog.components[Self.templateComponentID] else {
            throw Sikarugir11Error.notInCatalog(Self.templateComponentID)
        }
        let engineRoot = try await componentManager.install(id: Self.engineComponentID, component: engine)
        if Self.isAssembled(engineRoot: engineRoot, templateVersion: template.version) {
            refresh()
            return
        }
        let templateRoot = try await componentManager.install(
            id: Self.templateComponentID, component: template)
        guard let app = Self.templateApp(in: templateRoot) else {
            throw Sikarugir11Error.rendererMissing(templateRoot.path)
        }
        try await Self.assemble(engineRoot: engineRoot, templateApp: app)
        try? Data(template.version.utf8).write(to: engineRoot.appending(path: Self.assembledMarker))
        refresh()
    }

    nonisolated static func isAssembled(engineRoot: URL, templateVersion: String) -> Bool {
        let marker = engineRoot.appending(path: assembledMarker)
        guard let text = try? String(contentsOf: marker, encoding: .utf8) else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == templateVersion
    }

    /// The `.app` inside an extracted template component.
    nonisolated static func templateApp(in root: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.pathExtension == "app" }
    }

    /// The renderer inside a template. Newer templates keep it under
    /// SharedSupport; older ones under Frameworks.
    nonisolated static func renderer(in templateApp: URL) -> URL? {
        let candidates = [
            "Contents/SharedSupport/renderer/d3dmetal",
            "Contents/Frameworks/renderer/d3dmetal",
        ]
        return candidates
            .map { templateApp.appending(path: $0, directoryHint: .isDirectory) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Lays the renderer, the support dylibs and GStreamer into the engine,
    /// and gives the wineserver a library path.
    nonisolated static func assemble(engineRoot: URL, templateApp: URL) async throws {
        guard let renderer = renderer(in: templateApp) else {
            throw Sikarugir11Error.rendererMissing(templateApp.path)
        }
        let bundle = engineRoot.appending(path: "wswine.bundle", directoryHint: .isDirectory)
        let lib = bundle.appending(path: "lib", directoryHint: .isDirectory)
        try overlay(renderer: renderer, intoLib: lib)

        // libinotify, freetype, gnutls… — the engine tarball carries none of
        // them; Sikarugir keeps them in the template's Frameworks. GStreamer
        // is a framework there, copied whole (links preserved).
        let frameworks = templateApp.appending(path: "Contents/Frameworks", directoryHint: .isDirectory)
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)) ?? [] {
            guard item.pathExtension == "dylib" || item.lastPathComponent == "GStreamer.framework" else {
                continue
            }
            try replaceItem(at: lib.appending(path: item.lastPathComponent), with: item)
        }

        // The wineserver links @rpath/libinotify.0.dylib with no LC_RPATH of
        // its own (Sikarugir's launcher supplies DYLD paths instead), and
        // Fable runs it bare to drain prefixes. Every step is checked: the
        // marker written after this would stop a broken engine from ever
        // being re-assembled. Signing is checked on its own so a run that
        // stopped between the two steps gets repaired.
        let wineserver = bundle.appending(path: "bin/wineserver")
        if try await !hasLibraryRpath(wineserver) {
            try await checked("/usr/bin/install_name_tool", ["-add_rpath", "@loader_path/../lib", wineserver.path])
            guard try await hasLibraryRpath(wineserver) else {
                throw Sikarugir11Error.toolFailed("the wineserver still has no library path")
            }
        }
        let verify = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/codesign"), arguments: ["--verify", wineserver.path])
        if !verify.succeeded {
            try await checked("/usr/bin/codesign", ["--force", "--sign", "-", wineserver.path])
        }

        // Rosetta refuses quarantined dylibs by killing the process.
        _ = try? await ProcessRunner.run(
            URL(filePath: "/usr/bin/xattr"), arguments: ["-dr", "com.apple.quarantine", engineRoot.path])
    }

    nonisolated static func hasLibraryRpath(_ binary: URL) async throws -> Bool {
        let probe = try await ProcessRunner.run(URL(filePath: "/usr/bin/otool"), arguments: ["-l", binary.path])
        guard probe.succeeded else {
            throw Sikarugir11Error.toolFailed("otool: \(probe.standardError.isEmpty ? "exit \(probe.exitCode)" : probe.standardError)")
        }
        return probe.standardOutput.contains("@loader_path/../lib")
    }

    nonisolated static func checked(_ tool: String, _ arguments: [String]) async throws {
        let result = try await ProcessRunner.run(URL(filePath: tool), arguments: arguments)
        guard result.succeeded else {
            let name = URL(filePath: tool).lastPathComponent
            throw Sikarugir11Error.toolFailed("\(name): \(result.standardError.isEmpty ? "exit \(result.exitCode)" : result.standardError)")
        }
    }

    /// Copies the renderer's PE DLLs, host-side libraries and `external/`
    /// into the engine, preserving symbolic links. The host-side `.so` files
    /// are links to one `libd3dshared.dylib`; following them would load six
    /// copies of D3DMetal with six sets of state.
    nonisolated static func overlay(renderer: URL, intoLib lib: URL, layout: WineLayout = .rosetta) throws {
        let fm = FileManager.default
        let groups = [
            "wine/\(layout.peDirectory)",
            "wine/i386-windows",
            "wine/\(layout.unixDirectory)",
            "external",
        ]
        for group in groups {
            let source = renderer.appending(path: group, directoryHint: .isDirectory)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = lib.appending(path: group, directoryHint: .isDirectory)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                try replaceItem(at: destination.appending(path: item.lastPathComponent), with: item)
            }
        }
    }

    /// Replaces whatever is at `target` (file, directory, or a link — even a
    /// dangling one, which `fileExists` can't see) with a copy of `source`.
    /// `copyItem` copies a symbolic link as a link.
    nonisolated static func replaceItem(at target: URL, with source: URL) throws {
        let fm = FileManager.default
        if (try? fm.attributesOfItem(atPath: target.path)) != nil {
            try fm.removeItem(at: target)
        }
        try fm.copyItem(at: source, to: target)
    }

    // MARK: Binaries

    func engineRoot() throws -> URL {
        guard let engine = catalog.components[Self.engineComponentID],
              let root = componentManager.installedDirectory(for: Self.engineComponentID, version: engine.version),
              let template = catalog.components[Self.templateComponentID],
              Self.isAssembled(engineRoot: root, templateVersion: template.version)
        else {
            throw ComponentError.notInstalled(Self.engineComponentID)
        }
        return root
    }

    func wineBinary() throws -> URL {
        let root = try engineRoot()
        let wine = root.appending(path: "wswine.bundle/bin/wine")
        guard FileManager.default.isExecutableFile(atPath: wine.path) else {
            throw Sikarugir11Error.binaryNotFound(root.path)
        }
        return wine
    }

    func wineserverBinary() throws -> URL {
        try wineBinary().deletingLastPathComponent().appending(path: "wineserver")
    }

    // MARK: Launch

    /// The environment every process on this engine needs. `bundleRoot` is
    /// `…/wswine.bundle`; nil leaves out the paths (tests).
    nonisolated static func launchEnvironment(baseOverrides: String, bundleRoot: URL?) -> [String: String] {
        var env: [String: String] = [
            // D3DMetal's DLLs are forced in the registry — see builtinDLLs.
            "WINEDLLOVERRIDES": baseOverrides,
            "WINEMSYNC": "1",
            // Presence is what counts — see the type's documentation.
            "SikarugirAppWine11": "1",
        ]
        guard let bundleRoot else { return env }
        let lib = bundleRoot.appending(path: "lib", directoryHint: .isDirectory)
        let gstreamer = lib.appending(path: "GStreamer.framework/Libraries", directoryHint: .isDirectory)
        env["DYLD_FALLBACK_LIBRARY_PATH"] = [
            lib.path, gstreamer.path, "/usr/lib", "/usr/libexec", "/usr/lib/system",
        ].joined(separator: ":")
        env["GST_PLUGIN_PATH"] = gstreamer.appending(path: "gstreamer-1.0").path
        let external = lib.appending(path: "external", directoryHint: .isDirectory)
        let framework = external.appending(path: "D3DMetal.framework/Versions/A/D3DMetal")
        if FileManager.default.fileExists(atPath: framework.path) {
            env["D3DMETAL_FRAMEWORK_PATH"] = framework.path
        }
        let d3dshared = external.appending(path: "libd3dshared.dylib")
        if FileManager.default.fileExists(atPath: d3dshared.path) {
            env["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = d3dshared.path
        }
        return env
    }

    // MARK: Prefix registry

    /// The DLL overrides this engine needs in the prefix: D3DMetal's DLLs
    /// builtin for everything, and disabled for Steam's web helper — with
    /// D3DMetal its GPU process crashes in `dxgi` and Steam never signs in,
    /// while software rendering is all it needs. As (key, value, data).
    nonisolated static let registryOverrides: [(key: String, value: String, data: String)] =
        builtinDLLs.map { (#"Software\Wine\DllOverrides"#, $0, "builtin") }
        + builtinDLLs.map { (#"Software\Wine\AppDefaults\steamwebhelper.exe\DllOverrides"#, $0, "") }

    /// True when `user.reg` is missing any of ``registryOverrides``. The file
    /// can lag a running wineserver, so a stale read only costs a redundant
    /// (idempotent) write.
    nonisolated static func needsRegistryOverrides(userReg: String) -> Bool {
        registryOverrides.contains { entry in
            // user.reg doubles every backslash in key names.
            let header = "[" + entry.key.replacingOccurrences(of: #"\"#, with: #"\\"#) + "]"
            guard let start = userReg.range(of: header) else { return true }
            let section = userReg[start.upperBound...]
            let body = section.range(of: "\n[").map { section[..<$0.lowerBound] } ?? section
            return !body.contains(#""\#(entry.value)"="\#(entry.data)""#)
        }
    }

    /// The `wine reg add` argument vectors that write ``registryOverrides``.
    nonisolated static func registryCommands() -> [[String]] {
        registryOverrides.map {
            ["reg", "add", #"HKCU\"# + $0.key, "/v", $0.value, "/t", "REG_SZ", "/d", $0.data, "/f"]
        }
    }

    /// Writes the overrides when the prefix lacks them, through this engine's
    /// own wine so the write lands in the wineserver the launch then uses.
    func ensureRegistryOverrides(prefix: URL, baseEnvironment: [String: String]) async {
        let userReg = (try? String(contentsOf: prefix.appending(path: "user.reg"), encoding: .utf8)) ?? ""
        guard Self.needsRegistryOverrides(userReg: userReg), let wine = try? wineBinary() else { return }
        var environment = baseEnvironment
        environment.merge(Self.launchEnvironment(
            baseOverrides: baseEnvironment["WINEDLLOVERRIDES"] ?? "",
            bundleRoot: wine.deletingLastPathComponent().deletingLastPathComponent()
        )) { _, new in new }
        for arguments in Self.registryCommands() {
            _ = try? await ProcessRunner.run(wine, arguments: arguments, environment: environment)
        }
    }
}
