import Foundation

enum SikarugirError: LocalizedError {
    case notInstalled
    case engineTarballMissing(String)
    case rendererMissing(String)
    case binaryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Sikarugir isn't installed. Get it from sikarugir.app, then this backend works without further setup."
        case .engineTarballMissing(let path):
            "Sikarugir is installed but its Wine engine tarball wasn't found under \(path)."
        case .rendererMissing(let path):
            "Sikarugir's D3DMetal renderer wasn't found under \(path)."
        case .binaryNotFound(let searched):
            "Sikarugir engine extracted but no wine binary was found under \(searched)."
        }
    }
}

/// The breakthrough D3D12-on-Metal backend: Sikarugir ships a modern
/// Wine (10.0) engine PLUS a D3DMetal renderer whose dispatch DLLs are
/// recompiled against that same wine. This is the matched pair Apple's
/// GPTK lacks — GPTK binds D3DMetal to wine-7.7 whose SEH can't unwind
/// modern MSVC C++ exceptions (the 007 First Light int3 wall).
///
/// Fable doesn't ship any of this (D3DMetal.framework is Apple's). It
/// discovers Sikarugir on disk, extracts the GPL wine engine into its
/// own component dir, and overlays Sikarugir's d3dmetal renderer onto
/// it. Both engine and renderer dispatch are GPL Wine code; only the
/// framework is Apple's, sourced from the user's existing install.
@MainActor
final class SikarugirManager: ObservableObject {
    let componentManager: ComponentManager

    static let componentID = "sikarugir"

    /// D3D DLLs D3DMetal provides as Wine builtins. Forced builtin at
    /// launch so any native DLLs in the prefix don't shadow them.
    nonisolated static let builtinDLLs = ["d3d11", "d3d12", "dxgi", "nvapi64"]

    /// Sikarugir's on-disk home.
    nonisolated static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Sikarugir", directoryHint: .isDirectory)
    }

    @Published private(set) var isDiscovered = false

    init(componentManager: ComponentManager) {
        self.componentManager = componentManager
        refresh()
    }

    func refresh() {
        isDiscovered = (try? engineTarball()) != nil && (try? d3dMetalRenderer()) != nil
    }

    var isInstalled: Bool {
        (try? wineBinary()) != nil
    }

    // MARK: Discovery (Sikarugir's install on disk)

    /// The wine 10.0 engine tarball Sikarugir ships (extracted per-bottle
    /// by Sikarugir itself; Fable extracts its own copy).
    nonisolated func engineTarball() throws -> URL {
        let engines = Self.supportDirectory.appending(path: "Engines", directoryHint: .isDirectory)
        let tarballs = (try? FileManager.default.contentsOfDirectory(
            at: engines, includingPropertiesForKeys: nil
        )) ?? []
        guard let tarball = tarballs.first(where: {
            $0.lastPathComponent.hasPrefix("WS") && $0.pathExtension == "xz"
        }) else {
            throw SikarugirError.engineTarballMissing(engines.path)
        }
        return tarball
    }

    /// The d3dmetal renderer directory inside Sikarugir's Template app.
    /// Holds wine/x86_64-{windows,unix} dispatch + external/framework.
    nonisolated func d3dMetalRenderer() throws -> URL {
        let templateRoot = Self.supportDirectory.appending(path: "Template", directoryHint: .isDirectory)
        let templates = (try? FileManager.default.contentsOfDirectory(
            at: templateRoot, includingPropertiesForKeys: nil
        )) ?? []
        for template in templates where template.pathExtension == "app" {
            let renderer = template
                .appending(path: "Contents/Frameworks/renderer/d3dmetal", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: renderer.path) {
                return renderer
            }
        }
        throw SikarugirError.rendererMissing(templateRoot.path)
    }

    // MARK: Install (extract engine + overlay d3dmetal)

    /// Extracts Sikarugir's wine 10.0 engine into Fable's components and
    /// overlays the d3dmetal renderer. Idempotent — skips if the engine
    /// is already extracted with the renderer present.
    func ensureInstalled() async throws {
        guard isDiscovered else { throw SikarugirError.notInstalled }
        if isInstalled { return }

        let tarball = try engineTarball()
        let renderer = try d3dMetalRenderer()

        // Version label from the tarball name (WS12WineSikarugir10.0_4).
        let version = tarball.deletingPathExtension().deletingPathExtension().lastPathComponent
        let installRoot = AppPaths.components
            .appending(path: Self.componentID, directoryHint: .isDirectory)
            .appending(path: version, directoryHint: .isDirectory)

        let fm = FileManager.default
        try fm.createDirectory(at: installRoot, withIntermediateDirectories: true)

        // 1. Extract the engine (wswine.bundle/…) into the component dir.
        let extract = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"),
            arguments: ["-xJf", tarball.path, "-C", installRoot.path]
        )
        guard extract.succeeded else {
            throw ComponentError.extractionFailed(extract.standardError)
        }

        // 2. Overlay the d3dmetal renderer onto the engine's lib tree.
        let bundle = installRoot.appending(path: "wswine.bundle", directoryHint: .isDirectory)
        let lib = bundle.appending(path: "lib", directoryHint: .isDirectory)
        try Self.overlay(renderer: renderer, intoLib: lib)

        // 3. Strip quarantine — Rosetta-loaded wine fails dlopen on
        //    quarantined dylibs/frameworks otherwise.
        _ = try? await ProcessRunner.run(
            URL(filePath: "/usr/bin/xattr"),
            arguments: ["-dr", "com.apple.quarantine", installRoot.path]
        )

        try? Data("Sikarugir D3DMetal (\(version))".utf8)
            .write(to: installRoot.appending(path: ".d3dmetal-version"))

        refresh()
    }

    /// Copies the renderer's three payload groups into the engine lib:
    /// wine/x86_64-windows/*.dll, wine/x86_64-unix/*.so, external/*.
    nonisolated private static func overlay(renderer: URL, intoLib lib: URL) throws {
        let fm = FileManager.default
        let groups = [
            ("wine/x86_64-windows", "wine/x86_64-windows"),
            ("wine/x86_64-unix", "wine/x86_64-unix"),
            ("external", "external"),
        ]
        for (src, dst) in groups {
            let source = renderer.appending(path: src, directoryHint: .isDirectory)
            let destination = lib.appending(path: dst, directoryHint: .isDirectory)
            guard fm.fileExists(atPath: source.path) else { continue }
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                let target = destination.appending(path: item.lastPathComponent)
                if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    // MARK: Binaries

    func wineBinary() throws -> URL {
        guard let root = componentManager.installedDirectory(for: Self.componentID) else {
            throw ComponentError.notInstalled(Self.componentID)
        }
        let candidate = root
            .appending(path: "wswine.bundle/bin/wine64")
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        let fallback = root.appending(path: "wswine.bundle/bin/wine")
        if FileManager.default.isExecutableFile(atPath: fallback.path) {
            return fallback
        }
        throw SikarugirError.binaryNotFound(root.path)
    }

    func wineserverBinary() throws -> URL {
        try wineBinary().deletingLastPathComponent().appending(path: "wineserver")
    }

    // MARK: Launch

    /// Forces the D3DMetal-backed builtin d3d DLLs so nothing in the
    /// prefix's system32 shadows them. WINEESYNC matches Sikarugir's
    /// own launch defaults.
    nonisolated static func launchEnvironment(baseOverrides: String) -> [String: String] {
        [
            "WINEDLLOVERRIDES": "\(baseOverrides);\(builtinDLLs.joined(separator: ","))=b",
            "WINEESYNC": "1",
        ]
    }
}
