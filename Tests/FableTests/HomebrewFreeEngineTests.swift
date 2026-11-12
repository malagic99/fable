import Foundation
import Testing
@testable import Fable

/// v1.2: nothing before the first game may need Homebrew or Terminal. The
/// Wine 10 engine used to come from a Sikarugir install (a Homebrew cask);
/// it is now a pinned download, like every other engine.
@Suite("Homebrew-free Wine 10 engine")
struct HomebrewFreeEngineTests {

    private func bundledCatalog() throws -> VersionCatalog {
        try VersionCatalog.loadBundled()
    }

    @Test
    func catalogCarriesTheEngineAndItsOwnTemplate() throws {
        let catalog = try bundledCatalog()
        let engine = try #require(catalog.components[SikarugirManager.componentID])
        let template = try #require(catalog.components[SikarugirManager.templateComponentID])
        // The version is the folder name bottles are pinned to, so it has to
        // match what the pre-1.2 extraction called it.
        #expect(engine.version == "WS12WineSikarugir10.0_4")
        #expect(engine.url.lastPathComponent == "\(engine.version).tar.xz")
        #expect(ChecksumVerifier.isPinned(engine.sha256))
        #expect(ChecksumVerifier.isPinned(template.sha256))
        // A renderer is tied to one Wine generation: the Wine 11 path's
        // template must not be the one paired with Wine 10.
        #expect(SikarugirManager.templateComponentID != Sikarugir11Manager.templateComponentID)
        #expect(template.version != catalog.components[Sikarugir11Manager.templateComponentID]?.version)
    }

    @Test
    func aNewerInstalledEngineIsNeverOfferedADowngrade() {
        #expect(SikarugirManager.versionToOffer(
            available: "WS12WineSikarugir10.0_4", installed: "WS12WineSikarugir10.0_8")
            == "WS12WineSikarugir10.0_8")
        #expect(SikarugirManager.versionToOffer(
            available: "WS12WineSikarugir10.0_10", installed: "WS12WineSikarugir10.0_4")
            == "WS12WineSikarugir10.0_10")
        #expect(SikarugirManager.versionToOffer(
            available: "WS12WineSikarugir10.0_4", installed: nil) == "WS12WineSikarugir10.0_4")
        #expect(SikarugirManager.versionToOffer(available: nil, installed: "x") == nil)
    }

    @Test
    func theDownloadedTemplateSuppliesTheRenderer() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "fable-hbfree-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(SikarugirManager.downloadedRenderer(componentsRoot: root) == nil)

        func makeTemplate(_ version: String, withRenderer: Bool) throws {
            let app = root.appending(path: "\(SikarugirManager.templateComponentID)/\(version)/Template-\(version).app")
            let renderer = app.appending(path: "Contents/Frameworks/renderer/d3dmetal")
            try FileManager.default.createDirectory(
                at: withRenderer ? renderer : app, withIntermediateDirectories: true)
        }
        try makeTemplate("1.0.9", withRenderer: true)
        try makeTemplate("1.0.10", withRenderer: true)
        let newest = try #require(SikarugirManager.downloadedRenderer(componentsRoot: root))
        // Numeric order: 1.0.10 is newer than 1.0.9.
        #expect(newest.path.contains("/1.0.10/"))

        // A newer template with no renderer is skipped, not trusted.
        try makeTemplate("1.0.11", withRenderer: false)
        let fallback = try #require(SikarugirManager.downloadedRenderer(componentsRoot: root))
        #expect(fallback.path.contains("/1.0.10/"))
    }

    @Test
    func winetricksFindsTheBundledCabextractFirst() throws {
        let tools = FileManager.default.temporaryDirectory
            .appending(path: "fable-tools-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tools) }

        // Nothing bundled: no bogus entry, Homebrew's directories still there.
        #expect(WinetricksManager.toolSearchPath(base: "/usr/bin", bundledTools: tools)
            == "/opt/homebrew/bin:/usr/local/bin:/usr/bin")

        let cabextract = tools.appending(path: "cabextract")
        try Data("#!/bin/sh\n".utf8).write(to: cabextract)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cabextract.path)
        #expect(WinetricksManager.toolSearchPath(base: "/usr/bin", bundledTools: tools)
            == "\(tools.path):/opt/homebrew/bin:/usr/local/bin:/usr/bin")
    }
}

/// Opt-in, because it downloads ~270 MB: installs the Wine 10 engine into an
/// empty directory exactly as a Mac with no Sikarugir and no Homebrew would.
/// `FABLE_LIVE_ENGINE_DIR=/some/empty/dir swift test --filter LiveEngine`
@Suite("Live engine download", .enabled(if: ProcessInfo.processInfo.environment["FABLE_LIVE_ENGINE_DIR"] != nil))
struct LiveEngineDownloadTests {
    @Test @MainActor
    func aCleanMacGetsAWorkingEngineFromTheCatalogAlone() async throws {
        let root = URL(filePath: ProcessInfo.processInfo.environment["FABLE_LIVE_ENGINE_DIR"]!)
        let componentsDir = root.appending(path: "Components", directoryHint: .isDirectory)
        let downloadsDir = root.appending(path: "Downloads", directoryHint: .isDirectory)
        for dir in [componentsDir, downloadsDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let components = ComponentManager(
            componentsDirectory: componentsDir, downloadsDirectory: downloadsDir)
        let manager = SikarugirManager(
            componentManager: components, catalog: try VersionCatalog.loadBundled())
        #expect(!manager.isInstalled)
        try await manager.ensureInstalled()

        #expect(manager.isInstalled)
        let bundle = try manager.bundleRoot()
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: bundle.appending(path: "lib/external/D3DMetal.framework/Versions/A/D3DMetal").path))
        #expect(fm.fileExists(atPath: bundle.appending(path: "lib/wine/x86_64-unix/d3d12.so").path))
        #expect(fm.fileExists(atPath: bundle.appending(path: "lib/libfreetype.6.dylib").path))
        let version = try await ProcessRunner.run(try manager.wineBinary(), arguments: ["--version"])
        #expect(version.standardOutput.contains("wine-10"))
    }
}
