import Foundation
import Testing
@testable import Fable

@MainActor
@Suite struct DXMTManagerTests {
    /// Builds a fake installed DXMT component (mirroring the real tarball
    /// layout), a fake Wine install, and a bottle with a prefix skeleton.
    private func makeFixture() throws -> (DXMTManager, WineManager, BottleManager, Bottle, URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appending(path: "DXMTTests-\(UUID().uuidString)", directoryHint: .isDirectory)

        // Installed DXMT component with the nested v0.80/ folder.
        let dxmtDir = root.appending(path: "Components/dxmt/0.80/v0.80")
        for (dir, file) in [
            ("x86_64-windows", "d3d11.dll"), ("x86_64-windows", "dxgi.dll"),
            ("x86_64-windows", "d3d10core.dll"), ("x86_64-windows", "winemetal.dll"),
            ("i386-windows", "d3d11.dll"), ("x86_64-unix", "winemetal.so"),
        ] {
            let d = dxmtDir.appending(path: dir)
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            try Data(file.utf8).write(to: d.appending(path: file))
        }

        // Fake Wine: bin/wine + lib/wine/x86_64-unix.
        let wineRoot = root.appending(path: "Components/wine/11.0_1/wine")
        try fm.createDirectory(at: wineRoot.appending(path: "bin"), withIntermediateDirectories: true)
        try fm.createDirectory(
            at: wineRoot.appending(path: "lib/wine/x86_64-unix"),
            withIntermediateDirectories: true
        )
        let wineBin = wineRoot.appending(path: "bin/wine")
        try Data("#!/bin/sh\n".utf8).write(to: wineBin)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wineBin.path)

        let componentManager = ComponentManager(
            componentsDirectory: root.appending(path: "Components"),
            downloadsDirectory: root.appending(path: "Downloads")
        )
        let catalog = VersionCatalog(components: [:])
        let wineManager = WineManager(componentManager: componentManager, catalog: catalog)
        let dxmtManager = DXMTManager(componentManager: componentManager, catalog: catalog)

        let bottleManager = BottleManager(bottlesDirectory: root.appending(path: "Bottles"))
        let bottle = try bottleManager.createBottle(name: "DXMT Test")
        for windowsDir in ["windows/system32", "windows/syswow64"] {
            try fm.createDirectory(
                at: bottleManager.driveCDirectory(for: bottle).appending(path: windowsDir),
                withIntermediateDirectories: true
            )
        }

        return (dxmtManager, wineManager, bottleManager, bottle, root)
    }

    @Test
    func enableCopiesDLLsAndUnixBridge() throws {
        let (dxmt, wine, bottles, bottle, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(!dxmt.isEnabled(in: bottle, bottleManager: bottles))
        try dxmt.enable(in: bottle, bottleManager: bottles, wineManager: wine)

        let windows = bottles.driveCDirectory(for: bottle).appending(path: "windows")
        for dll in ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"] {
            #expect(FileManager.default.fileExists(
                atPath: windows.appending(path: "system32/\(dll)").path), "missing \(dll)")
        }
        #expect(FileManager.default.fileExists(
            atPath: windows.appending(path: "syswow64/d3d11.dll").path))

        let bridge = root.appending(
            path: "Components/wine/11.0_1/wine/lib/wine/x86_64-unix/winemetal.so")
        #expect(FileManager.default.fileExists(atPath: bridge.path))

        #expect(dxmt.isEnabled(in: bottle, bottleManager: bottles))
        // Idempotent.
        try dxmt.enable(in: bottle, bottleManager: bottles, wineManager: wine)
    }

    @Test
    func launchEnvironmentRoutesOverridesByEnabledState() {
        let enabled = DXMTManager.launchEnvironment(
            enabled: true,
            config: DXMTConfig(maxFrameRate: 60),
            baseOverrides: "mscoree,mshtml=",
            logFile: URL(filePath: "/tmp/logs/game.log")
        )
        #expect(enabled["WINEDLLOVERRIDES"] == "mscoree,mshtml=;d3d10core,d3d11,dxgi,nvapi64=n")
        #expect(enabled["DXMT_CONFIG"] == "dxgi.maxFrameRate=60;")
        #expect(enabled["DXMT_LOG_LEVEL"] == "error")
        #expect(enabled["DXMT_LOG_PATH"] == "/tmp/logs")

        let disabled = DXMTManager.launchEnvironment(
            enabled: false,
            config: DXMTConfig(),
            baseOverrides: "mscoree,mshtml=",
            logFile: nil
        )
        #expect(disabled["WINEDLLOVERRIDES"] == "mscoree,mshtml=;d3d10core,d3d11,dxgi,nvapi64=b")
        #expect(disabled["DXMT_CONFIG"] == nil)
        #expect(disabled["DXMT_LOG_LEVEL"] == nil)
    }

    @Test
    func bottleDXMTSettingsPersist() throws {
        let (_, _, bottles, bottle, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        try bottles.setDXMT(enabled: true, config: DXMTConfig(maxFrameRate: 120), for: bottle.id)

        let reloaded = BottleManager(bottlesDirectory: bottles.bottlesDirectory)
        let persisted = try #require(reloaded.bottle(with: bottle.id))
        #expect(persisted.dxmtEnabled)
        #expect(persisted.dxmtConfig.maxFrameRate == 120)
    }
}
