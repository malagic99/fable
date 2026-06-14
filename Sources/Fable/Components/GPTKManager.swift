import Foundation

enum GPTKError: LocalizedError {
    case notInCatalog
    case binaryNotFound(String)
    case dmgMountFailed(String)
    case redistNotFound

    var errorDescription: String? {
        switch self {
        case .notInCatalog:
            "The version catalog has no Game Porting Toolkit entry."
        case .binaryNotFound(let searched):
            "Game Porting Toolkit is installed but no wine binary was found under \(searched)."
        case .dmgMountFailed(let detail):
            "Couldn't open the disk image: \(detail)"
        case .redistNotFound:
            "That disk image doesn't contain the evaluation environment's redist/lib payload. Mount Apple's Game Porting Toolkit dmg and use the nested “Evaluation environment for Windows games” image."
        }
    }
}

/// Owns the Game Porting Toolkit environment: a CrossOver-based Wine
/// with Apple's D3DMetal (D3D9–12 → Metal). Serves two roles: graphics
/// backend for D3D12 games, and the 32-bit installer compatibility
/// runtime (CompatibilityRuntime discovers it first).
@MainActor
final class GPTKManager: ObservableObject {
    let componentManager: ComponentManager
    let catalog: VersionCatalog

    static let componentID = "gptk"

    /// D3D DLLs provided by GPTK as Wine builtins. When the GPTK
    /// backend runs a game these are forced builtin so DXMT's native
    /// DLLs in system32 don't shadow them.
    nonisolated static let builtinDLLs = ["d3d10core", "d3d11", "d3d12", "dxgi", "nvapi64", "nvngx-on-metalfx"]

    init(componentManager: ComponentManager, catalog: VersionCatalog) {
        self.componentManager = componentManager
        self.catalog = catalog
    }

    var isInstalled: Bool {
        (try? wineBinary()) != nil
    }

    /// Version of Apple's D3DMetal currently in the environment
    /// (bumped by overlayEvaluationLibraries).
    var d3dMetalVersionNote: String? {
        guard let root = componentManager.installedDirectory(for: Self.componentID) else {
            return nil
        }
        let marker = root.appending(path: ".d3dmetal-version")
        return try? String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func ensureInstalled() async throws {
        guard let gptk = catalog.components[Self.componentID] else { throw GPTKError.notInCatalog }
        try await componentManager.install(id: Self.componentID, component: gptk)
    }

    func wineBinary() throws -> URL {
        guard let root = componentManager.installedDirectory(for: Self.componentID) else {
            throw ComponentError.notInstalled(Self.componentID)
        }
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                let path = url.path
                if path.hasSuffix("/bin/wine64") || path.hasSuffix("/bin/wine"),
                   fm.isExecutableFile(atPath: path) {
                    return url
                }
            }
        }
        throw GPTKError.binaryNotFound(root.path)
    }

    func wineserverBinary() throws -> URL {
        try wineBinary().deletingLastPathComponent().appending(path: "wineserver")
    }

    /// The wine/lib directory holding D3DMetal.framework and the
    /// d3d*.dll/.so bridge files.
    private func libDirectory() throws -> URL {
        try wineBinary()                       // …/wine/bin/wine64
            .deletingLastPathComponent()       // …/wine/bin
            .deletingLastPathComponent()       // …/wine
            .appending(path: "lib", directoryHint: .isDirectory)
    }

    // MARK: Apple dmg overlay

    /// Replaces the environment's D3DMetal with the (newer) libraries
    /// from Apple's evaluation-environment dmg, per the dmg's README:
    /// redist/lib/* over wine/lib/*.
    func overlayEvaluationLibraries(fromDMG dmg: URL, versionLabel: String) async throws {
        let mountPoint = try await mount(dmg)
        defer { Task { try? await Self.detach(mountPoint) } }

        // The payload may be in the given dmg, or in a nested
        // "Evaluation environment" dmg inside the developer kit image.
        var redistLib = mountPoint.appending(path: "redist/lib", directoryHint: .isDirectory)
        var nestedMount: URL?
        if !FileManager.default.fileExists(atPath: redistLib.path) {
            guard let nested = try? FileManager.default
                .contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
                .first(where: {
                    $0.pathExtension.lowercased() == "dmg"
                        && $0.lastPathComponent.localizedCaseInsensitiveContains("evaluation")
                }) else {
                throw GPTKError.redistNotFound
            }
            let inner = try await mount(nested)
            nestedMount = inner
            redistLib = inner.appending(path: "redist/lib", directoryHint: .isDirectory)
        }
        defer {
            if let nestedMount {
                Task { try? await Self.detach(nestedMount) }
            }
        }
        guard FileManager.default.fileExists(atPath: redistLib.path) else {
            throw GPTKError.redistNotFound
        }

        let lib = try libDirectory()
        try Self.merge(redistLib, into: lib)

        if let root = componentManager.installedDirectory(for: Self.componentID) {
            try? Data(versionLabel.utf8).write(
                to: root.appending(path: ".d3dmetal-version"))
            // Strip com.apple.quarantine recursively. Without this, Wine
            // (running under Rosetta) hits dlopen errors at d3d12 DllMain
            // and the game aborts with STATUS_DLL_INIT_FAILED (c0000142).
            // The dmg payload comes from Apple but inherits quarantine
            // from the user's browser download; the merge() doesn't drop
            // xattrs, so we explicitly clear them post-copy.
            try? await Self.stripQuarantine(at: root)
        }
    }

    nonisolated private static func stripQuarantine(at root: URL) async throws {
        _ = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/xattr"),
            arguments: ["-dr", "com.apple.quarantine", root.path]
        )
    }

    /// Recursive overwrite-merge of directory contents.
    nonisolated private static func merge(_ source: URL, into destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey]) {
            let target = destination.appending(path: item.lastPathComponent)
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            // Frameworks and bundles are replaced wholesale; plain
            // directories merge so unrelated files survive.
            if isDirectory && !item.lastPathComponent.hasSuffix(".framework") {
                try merge(item, into: target)
            } else {
                if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    nonisolated private func mount(_ dmg: URL) async throws -> URL {
        let result = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/hdiutil"),
            arguments: ["attach", "-nobrowse", "-readonly", "-plist", dmg.path]
        )
        guard result.succeeded else {
            throw GPTKError.dmgMountFailed(result.standardError)
        }
        // Parse the plist for the mount point.
        guard let data = result.standardOutput.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let entities = dict["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw GPTKError.dmgMountFailed("couldn't find the mount point")
        }
        return URL(filePath: mountPoint, directoryHint: .isDirectory)
    }

    nonisolated private static func detach(_ mountPoint: URL) async throws {
        _ = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/hdiutil"),
            arguments: ["detach", mountPoint.path, "-quiet"]
        )
    }

    // MARK: Launch environment

    /// Environment fragment for launching a game on the GPTK backend.
    /// GPTK's D3D DLLs are Wine builtins in its own tree — force
    /// builtin so DXMT's natives in system32 never shadow them.
    nonisolated static func launchEnvironment(baseOverrides: String) -> [String: String] {
        [
            "WINEDLLOVERRIDES": "\(baseOverrides);\(builtinDLLs.joined(separator: ","))=b",
            "WINEESYNC": "1",
        ]
    }
}
