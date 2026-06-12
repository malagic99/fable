import Foundation
import Testing
@testable import Fable

/// Full end-to-end check: install Wine from a local tarball, locate the
/// binary, and bootstrap a real prefix. Slow (about a minute) and needs a
/// downloaded tarball, so it only runs when FABLE_WINE_TARBALL is set:
///
///   FABLE_WINE_TARBALL=/tmp/wine-stable-11.0_1-osx64.tar.xz swift test \
///     --filter WineIntegrationTests
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FABLE_WINE_TARBALL"] != nil))
struct WineIntegrationTests {
    @Test(.timeLimit(.minutes(5)))
    func installsWineAndCreatesPrefix() async throws {
        let tarballPath = try #require(ProcessInfo.processInfo.environment["FABLE_WINE_TARBALL"])
        let tarball = URL(filePath: tarballPath)

        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appending(path: "WineIntegration-\(UUID().uuidString)", directoryHint: .isDirectory)
        let downloads = root.appending(path: "Downloads", directoryHint: .isDirectory)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let componentManager = ComponentManager(
            componentsDirectory: root.appending(path: "Components", directoryHint: .isDirectory),
            downloadsDirectory: downloads
        )
        let catalog = VersionCatalog(components: [
            "wine": .init(
                name: "Wine Stable",
                version: "11.0_1",
                url: tarball,
                sha256: try ChecksumVerifier.sha256(of: tarball)
            )
        ])
        let wineManager = WineManager(componentManager: componentManager, catalog: catalog)

        try await wineManager.ensureWineInstalled()
        let wine = try wineManager.wineBinary()
        #expect(FileManager.default.isExecutableFile(atPath: wine.path))

        let prefix = root.appending(path: "prefix", directoryHint: .isDirectory)
        try await wineManager.createPrefix(at: prefix, windowsVersion: .win10)

        #expect(fm.fileExists(atPath: prefix.appending(path: "drive_c").path))
        #expect(fm.fileExists(atPath: prefix.appending(path: "system.reg").path))
    }
}
