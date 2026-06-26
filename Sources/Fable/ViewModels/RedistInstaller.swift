import Foundation

/// Runs Windows redistributable installers (OpenAL, VC++, DirectX)
/// silently inside a bottle — the dependency steps a real installer
/// would have performed.
@MainActor
final class RedistInstaller: ObservableObject {
    enum Kind: Equatable {
        case openAL
        case vcRedist
        case directX
        case generic

        var displayName: String {
            switch self {
            case .openAL: "OpenAL audio runtime"
            case .vcRedist: "Visual C++ runtime"
            case .directX: "DirectX runtime (June 2010)"
            case .generic: "Installer"
            }
        }
    }

    @Published private(set) var currentInstall: String?

    nonisolated static func classify(_ installer: URL) -> Kind {
        let name = installer.lastPathComponent.lowercased()
        if name.contains("oalinst") || name.contains("openal") { return .openAL }
        if name.contains("vcredist") || name.contains("vc_redist") { return .vcRedist }
        if name.contains("directx") || name.contains("dxsetup") || name.contains("dxwebsetup") {
            return .directX
        }
        return .generic
    }

    nonisolated static func silentArguments(for kind: Kind) -> [String] {
        switch kind {
        case .openAL: ["/s"]
        case .vcRedist: ["/q", "/norestart"]
        // DirectX self-extractor handled separately in install().
        case .directX: []
        case .generic: ["/S"]
        }
    }

    /// Installs each redist silently, in order. Throws on the first
    /// hard failure (non-zero exits are logged but tolerated — plenty
    /// of redists exit non-zero for "already installed").
    func install(
        _ redists: [URL],
        bottle: Bottle,
        bottleManager: BottleManager,
        wineManager: WineManager
    ) async throws {
        defer { currentInstall = nil }
        for redist in redists {
            let kind = Self.classify(redist)
            currentInstall = kind == .generic ? redist.lastPathComponent : kind.displayName
            try await install(redist, kind: kind, bottle: bottle,
                              bottleManager: bottleManager, wineManager: wineManager)
        }
    }

    private func install(
        _ redist: URL,
        kind: Kind,
        bottle: Bottle,
        bottleManager: BottleManager,
        wineManager: WineManager
    ) async throws {
        let prefix = bottleManager.prefixDirectory(for: bottle)
        var environment = wineManager.environment(forPrefix: prefix)
        environment["WINEDEBUG"] = "fixme-all,-msync"
        let wine = try wineManager.wineBinary()

        if kind == .directX {
            // Two stages: self-extract the package, then run DXSETUP.
            let extractDir = "C:\\fable_dxredist"
            _ = try await ProcessRunner.run(
                wine,
                arguments: [redist.path, "/Q", "/T:\(extractDir)"],
                environment: environment
            )
            let dxsetup = bottleManager.driveCDirectory(for: bottle)
                .appending(path: "fable_dxredist/DXSETUP.exe")
            if FileManager.default.fileExists(atPath: dxsetup.path) {
                _ = try await ProcessRunner.run(
                    wine,
                    arguments: [dxsetup.path, "/silent"],
                    environment: environment
                )
            }
            try? FileManager.default.removeItem(
                at: bottleManager.driveCDirectory(for: bottle).appending(path: "fable_dxredist")
            )
            return
        }

        _ = try await ProcessRunner.run(
            wine,
            arguments: [redist.path] + Self.silentArguments(for: kind),
            environment: environment
        )
    }
}
