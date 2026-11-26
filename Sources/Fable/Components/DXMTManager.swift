import Foundation

enum DXMTError: LocalizedError {
    case notInCatalog
    case payloadNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notInCatalog:
            "The version catalog has no DXMT entry."
        case .payloadNotFound(let what):
            "The DXMT component is missing \(what). Try reinstalling it."
        }
    }
}

/// Installs DXMT (DirectX 11 over Metal) and enables it per bottle.
///
/// Fable ships its own DXMT build (scripts/build-dxmt.sh) in DXMT's *native*
/// mode. The package root holds:
///  - `system32/` and `syswow64/`: d3d11, dxgi, d3d10core (and nvapi64) as
///    plain Windows DLLs, copied into the bottle and forced native;
///  - `x86_64-windows/` and `i386-windows/`: winemetal.dll (and nvngx.dll),
///    which stay Wine builtins, plus `x86_64-unix/winemetal.so`, the Metal
///    bridge they call.
///
/// The builtins are copied into the bottle too, and the launch puts the
/// package root on `WINEDLLPATH`: Wine only looks a builtin up on
/// `WINEDLLPATH` when the bottle has a file by that name, and then loads the
/// matching winemetal.so from the same root. Nothing is written into the
/// Wine engine, so DXMT stays a per-bottle choice.
///
/// Upstream's release is the builtin build, which can't work this way: Wine
/// refuses a builtin-stamped DLL under a native override, and a builtin
/// override loads Wine's own d3d11 from the engine instead.
@MainActor
final class DXMTManager: ObservableObject {
    let componentManager: ComponentManager
    let catalog: VersionCatalog

    static let componentID = "dxmt"

    /// DLLs DXMT replaces; forced native when enabled, builtin when not.
    nonisolated static let overriddenDLLs = ["d3d10core", "d3d11", "dxgi", "nvapi64"]

    /// Package folders and the bottle folder each one is copied into.
    nonisolated static let stagedFolders = [
        ("system32", "system32"), ("x86_64-windows", "system32"),
        ("syswow64", "syswow64"), ("i386-windows", "syswow64"),
    ]

    init(componentManager: ComponentManager, catalog: VersionCatalog) {
        self.componentManager = componentManager
        self.catalog = catalog
    }

    var isInstalled: Bool { packageRoot() != nil }

    /// The version folder the package was found in ("0.80-fable.1").
    var installedVersion: String? {
        guard let root = packageRoot() else { return nil }
        let versions = componentManager.installedVersions(for: Self.componentID)
        return versions.contains(root.lastPathComponent)
            ? root.lastPathComponent
            : root.deletingLastPathComponent().lastPathComponent
    }

    /// Installs the catalog's DXMT and removes other installed versions:
    /// DXMT isn't pinned per bottle, and older installs are upstream's
    /// builtin build, which ``packageRoot(installedIn:)`` won't use anyway.
    func ensureInstalled() async throws {
        guard let dxmt = catalog.dxmt else { throw DXMTError.notInCatalog }
        let installed = try await componentManager.install(id: Self.componentID, component: dxmt)
        for version in componentManager.installedVersions(for: Self.componentID)
        where version != installed.lastPathComponent {
            if let old = componentManager.installedDirectory(for: Self.componentID, version: version) {
                try? FileManager.default.removeItem(at: old)
            }
        }
    }

    // MARK: Payload discovery

    /// The installed native-mode package root, if there is one.
    func packageRoot() -> URL? {
        Self.packageRoot(installedIn: componentManager.installedVersions(for: Self.componentID)
            .compactMap { componentManager.installedDirectory(for: Self.componentID, version: $0) })
    }

    /// First folder (newest version first) holding the native layout:
    /// `system32/d3d11.dll` and the Metal bridge. Looks one level down too,
    /// since the tarball nests everything in a `v<version>/` folder.
    nonisolated static func packageRoot(installedIn versionDirectories: [URL]) -> URL? {
        let fm = FileManager.default
        let sorted = versionDirectories.sorted {
            VersionCompare.isNewer($0.lastPathComponent, than: $1.lastPathComponent)
        }
        func isPackage(_ url: URL) -> Bool {
            fm.fileExists(atPath: url.appending(path: "system32/d3d11.dll").path)
                && fm.fileExists(atPath: url.appending(path: "x86_64-unix/winemetal.so").path)
        }
        for version in sorted {
            if isPackage(version) { return version }
            let children = (try? fm.contentsOfDirectory(
                at: version, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            if let match = children.first(where: isPackage) { return match }
        }
        return nil
    }

    // MARK: Enabling per bottle

    /// True when DXMT's DLLs are present in the bottle's system32.
    func isEnabled(in bottle: Bottle, bottleManager: BottleManager) -> Bool {
        let system32 = bottleManager.driveCDirectory(for: bottle)
            .appending(path: "windows/system32")
        return FileManager.default.fileExists(
            atPath: system32.appending(path: "winemetal.dll").path
        )
    }

    /// Copies DXMT's DLLs into the bottle. Idempotent; launches re-stage
    /// anyway, so a DXMT update reaches every bottle without this.
    ///
    /// Also removes the winemetal.so older Fable versions copied into the
    /// Wine engine: the engine doesn't ship one, and nothing should load a
    /// stale copy.
    func enable(in bottle: Bottle, bottleManager: BottleManager, wineManager: WineManager) throws {
        guard let package = packageRoot() else {
            throw DXMTError.payloadNotFound("its native-mode package")
        }
        try Self.stage(package: package, driveC: bottleManager.driveCDirectory(for: bottle))

        if let wineBinary = try? wineManager.wineBinary(
            forPrefix: bottleManager.prefixDirectory(for: bottle)) {
            let layout = WineLayout.detect(wineBinary: wineBinary)
            let legacy = wineBinary
                .deletingLastPathComponent()                // …/wine/bin
                .deletingLastPathComponent()                // …/wine
                .appending(path: "lib/wine/\(layout.unixDirectory)/winemetal.so")
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    /// Copies the package's DLLs into the bottle's system32 and syswow64,
    /// skipping files that are already identical. syswow64 is only filled
    /// when the bottle has one (a 64-bit-only prefix doesn't).
    nonisolated static func stage(package: URL, driveC: URL) throws {
        let fm = FileManager.default
        let windows = driveC.appending(path: "windows", directoryHint: .isDirectory)
        guard fm.fileExists(atPath: package.appending(path: "system32").path) else {
            throw DXMTError.payloadNotFound("its 64-bit DLLs")
        }
        for (source, target) in stagedFolders {
            let from = package.appending(path: source, directoryHint: .isDirectory)
            let to = windows.appending(path: target, directoryHint: .isDirectory)
            guard fm.fileExists(atPath: from.path) else { continue }
            if target == "syswow64" && !fm.fileExists(atPath: to.path) { continue }
            try fm.createDirectory(at: to, withIntermediateDirectories: true)
            for file in try fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil) {
                let dest = to.appending(path: file.lastPathComponent)
                if fm.fileExists(atPath: dest.path),
                   (try? ChecksumVerifier.sha256(of: dest)) == (try? ChecksumVerifier.sha256(of: file)) {
                    continue
                }
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: file, to: dest)
            }
        }
    }

    // MARK: Launch environment

    /// WINEDLLOVERRIDES fragment, WINEDLLPATH and DXMT env vars for a game
    /// launch. `package` is the native-mode package root; it is only used
    /// when `enabled`.
    nonisolated static func launchEnvironment(
        enabled: Bool,
        package: URL?,
        config: DXMTConfig,
        baseOverrides: String,
        logFile: URL?
    ) -> [String: String] {
        let direction = enabled ? "n" : "b"
        let overrides = "\(baseOverrides);\(overriddenDLLs.joined(separator: ","))=\(direction)"
        var env: [String: String] = ["WINEDLLOVERRIDES": overrides]
        if enabled {
            if let package { env["WINEDLLPATH"] = package.path }
            env.merge(config.environment(logFile: logFile)) { _, new in new }
        }
        return env
    }
}
