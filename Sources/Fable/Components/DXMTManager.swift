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
/// The "builtin" DXMT build has three pieces:
///  - PE DLLs (d3d11, dxgi, d3d10core, winemetal, nvapi64, nvngx) that go
///    into the prefix's system32 (64-bit) and syswow64 (32-bit),
///  - winemetal.so, the Metal bridge, which must sit in Wine's own
///    host-side library directory (``WineLayout/unixDirectory``),
///  - WINEDLLOVERRIDES at launch deciding whether games see DXMT's DLLs
///    (enabled → native, disabled → Wine's builtins). Toggling is just an
///    override change; files stay put.
@MainActor
final class DXMTManager: ObservableObject {
    let componentManager: ComponentManager
    let catalog: VersionCatalog

    static let componentID = "dxmt"

    /// DLLs DXMT replaces; forced native when enabled, builtin when not.
    nonisolated static let overriddenDLLs = ["d3d10core", "d3d11", "dxgi", "nvapi64"]

    init(componentManager: ComponentManager, catalog: VersionCatalog) {
        self.componentManager = componentManager
        self.catalog = catalog
    }

    var isInstalled: Bool {
        componentManager.installedDirectory(for: Self.componentID) != nil
    }

    func ensureInstalled() async throws {
        guard let dxmt = catalog.dxmt else { throw DXMTError.notInCatalog }
        try await componentManager.install(id: Self.componentID, component: dxmt)
    }

    // MARK: Payload discovery

    /// Finds a payload directory (the guest PE and host Unix directories named
    /// by ``WineLayout``) inside the installed component, tolerating the
    /// tarball's nested v0.80/ folder.
    private func payloadDirectory(named name: String) -> URL? {
        guard let root = componentManager.installedDirectory(for: Self.componentID) else {
            return nil
        }
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in enumerator where url.lastPathComponent == name {
                return url
            }
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

    /// Copies DXMT's DLLs into the bottle and the Metal bridge into the
    /// Wine installation. Idempotent.
    func enable(in bottle: Bottle, bottleManager: BottleManager, wineManager: WineManager) throws {
        let wineBinary = try wineManager.wineBinary()  // …/wine/bin/wine
        let layout = WineLayout.detect(wineBinary: wineBinary)

        guard let pe64 = payloadDirectory(named: layout.peDirectory) else {
            throw DXMTError.payloadNotFound("its 64-bit DLLs")
        }
        guard let unixLib = payloadDirectory(named: layout.unixDirectory) else {
            throw DXMTError.payloadNotFound("winemetal.so")
        }

        let fm = FileManager.default
        let windows = bottleManager.driveCDirectory(for: bottle).appending(path: "windows")

        try copyContents(of: pe64, to: windows.appending(path: "system32"))
        if let pe32 = payloadDirectory(named: layout.pe32Directory) {
            let syswow64 = windows.appending(path: "syswow64")
            if fm.fileExists(atPath: syswow64.path) {
                try copyContents(of: pe32, to: syswow64)
            }
        }

        // winemetal.so goes next to Wine's own unix libraries.
        let wineUnixDir = wineBinary
            .deletingLastPathComponent()                // …/wine/bin
            .deletingLastPathComponent()                // …/wine
            .appending(path: "lib/wine/\(layout.unixDirectory)", directoryHint: .isDirectory)
        guard fm.fileExists(atPath: wineUnixDir.path) else {
            throw DXMTError.payloadNotFound("Wine's \(layout.unixDirectory) library directory")
        }
        try copyContents(of: unixLib, to: wineUnixDir)
    }

    private func copyContents(of source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let target = destination.appending(path: file.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.copyItem(at: file, to: target)
        }
    }

    // MARK: Launch environment

    /// WINEDLLOVERRIDES fragment and DXMT env vars for a game launch.
    nonisolated static func launchEnvironment(
        enabled: Bool,
        config: DXMTConfig,
        baseOverrides: String,
        logFile: URL?
    ) -> [String: String] {
        let direction = enabled ? "n" : "b"
        let overrides = "\(baseOverrides);\(overriddenDLLs.joined(separator: ","))=\(direction)"
        var env: [String: String] = ["WINEDLLOVERRIDES": overrides]
        if enabled {
            env.merge(config.environment(logFile: logFile)) { _, new in new }
        }
        return env
    }
}
