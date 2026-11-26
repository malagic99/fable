import Foundation
import Testing
@testable import Fable

@MainActor
@Suite struct DXMTManagerTests {
    /// Builds a fake installed DXMT component (the native-mode package
    /// layout, nested in its v<version>/ folder), a fake Wine install, and a
    /// bottle with a prefix skeleton.
    private func makeFixture() throws -> (DXMTManager, WineManager, BottleManager, Bottle, URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appending(path: "DXMTTests-\(UUID().uuidString)", directoryHint: .isDirectory)

        let dxmtDir = root.appending(path: "Components/dxmt/0.80-fable.1/v0.80-fable.1")
        for (dir, file) in [
            ("system32", "d3d11.dll"), ("system32", "dxgi.dll"),
            ("system32", "d3d10core.dll"), ("system32", "nvapi64.dll"),
            ("syswow64", "d3d11.dll"), ("syswow64", "dxgi.dll"),
            ("x86_64-windows", "winemetal.dll"), ("x86_64-windows", "nvngx.dll"),
            ("i386-windows", "winemetal.dll"), ("x86_64-unix", "winemetal.so"),
        ] {
            let d = dxmtDir.appending(path: dir)
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            try Data("\(dir)/\(file)".utf8).write(to: d.appending(path: file))
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
    func enableStagesNativeAndBuiltinDLLsWithoutTouchingTheEngine() throws {
        let (dxmt, wine, bottles, bottle, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default

        // A winemetal.so an older Fable copied into the engine is removed.
        let legacy = root.appending(path: "Components/wine/11.0_1/wine/lib/wine/x86_64-unix/winemetal.so")
        try Data("old".utf8).write(to: legacy)

        #expect(dxmt.packageRoot()?.lastPathComponent == "v0.80-fable.1")
        #expect(!dxmt.isEnabled(in: bottle, bottleManager: bottles))
        try dxmt.enable(in: bottle, bottleManager: bottles, wineManager: wine)

        let windows = bottles.driveCDirectory(for: bottle).appending(path: "windows")
        for dll in ["system32/d3d11.dll", "system32/dxgi.dll", "system32/d3d10core.dll",
                    "system32/nvapi64.dll", "system32/winemetal.dll", "system32/nvngx.dll",
                    "syswow64/d3d11.dll", "syswow64/dxgi.dll", "syswow64/winemetal.dll"] {
            #expect(fm.fileExists(atPath: windows.appending(path: dll).path), "missing \(dll)")
        }
        // The 32-bit winemetal is the i386 one, not the 64-bit one.
        #expect(try String(contentsOf: windows.appending(path: "syswow64/winemetal.dll"), encoding: .utf8)
                == "i386-windows/winemetal.dll")
        #expect(!fm.fileExists(atPath: legacy.path))
        #expect(dxmt.isEnabled(in: bottle, bottleManager: bottles))
        // Idempotent.
        try dxmt.enable(in: bottle, bottleManager: bottles, wineManager: wine)
    }

    @Test
    func stageReplacesChangedFilesAndSkipsAMissingSyswow64() throws {
        let (dxmt, _, bottles, bottle, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let package = try #require(dxmt.packageRoot())
        let driveC = bottles.driveCDirectory(for: bottle)
        let syswow64 = driveC.appending(path: "windows/syswow64")
        try fm.removeItem(at: syswow64)

        let d3d11 = driveC.appending(path: "windows/system32/d3d11.dll")
        try DXMTManager.stage(package: package, driveC: driveC)
        try Data("stale".utf8).write(to: d3d11)
        try DXMTManager.stage(package: package, driveC: driveC)

        #expect(try String(contentsOf: d3d11, encoding: .utf8) == "system32/d3d11.dll")
        #expect(!fm.fileExists(atPath: syswow64.path))
    }

    @Test
    func upstreamBuiltinLayoutIsNotAPackage() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "DXMTOld-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        // Upstream v0.80's tarball: no system32/, everything under the
        // Wine-style folders.
        let old = root.appending(path: "0.80")
        for path in ["v0.80/x86_64-windows/d3d11.dll", "v0.80/x86_64-unix/winemetal.so"] {
            let file = old.appending(path: path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        #expect(DXMTManager.packageRoot(installedIn: [old]) == nil)

        let new = root.appending(path: "0.80-fable.1")
        for path in ["v0.80-fable.1/system32/d3d11.dll", "v0.80-fable.1/x86_64-unix/winemetal.so"] {
            let file = new.appending(path: path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        #expect(DXMTManager.packageRoot(installedIn: [old, new])?.lastPathComponent == "v0.80-fable.1")
    }

    @Test
    func launchEnvironmentRoutesOverridesByEnabledState() {
        let package = URL(filePath: "/c/dxmt/0.80-fable.1/v0.80-fable.1", directoryHint: .isDirectory)
        let enabled = DXMTManager.launchEnvironment(
            enabled: true,
            package: package,
            config: DXMTConfig(maxFrameRate: 60),
            baseOverrides: "mscoree,mshtml=",
            logFile: URL(filePath: "/tmp/logs/game.log")
        )
        #expect(enabled["WINEDLLOVERRIDES"] == "mscoree,mshtml=;d3d10core,d3d11,dxgi,nvapi64=n")
        #expect(enabled["WINEDLLPATH"] == "/c/dxmt/0.80-fable.1/v0.80-fable.1")
        #expect(enabled["DXMT_CONFIG"] == "dxgi.maxFrameRate=60;")
        #expect(enabled["DXMT_LOG_LEVEL"] == "error")
        #expect(enabled["DXMT_LOG_PATH"] == "/tmp/logs")

        let disabled = DXMTManager.launchEnvironment(
            enabled: false,
            package: package,
            config: DXMTConfig(),
            baseOverrides: "mscoree,mshtml=",
            logFile: nil
        )
        #expect(disabled["WINEDLLOVERRIDES"] == "mscoree,mshtml=;d3d10core,d3d11,dxgi,nvapi64=b")
        #expect(disabled["WINEDLLPATH"] == nil)
        #expect(disabled["DXMT_CONFIG"] == nil)
        #expect(disabled["DXMT_LOG_LEVEL"] == nil)
    }

    @Test
    func bottleGraphicsSettingsPersist() throws {
        let (_, _, bottles, bottle, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        try bottles.setGraphics(backend: .dxmt, config: DXMTConfig(maxFrameRate: 120), for: bottle.id)

        let reloaded = BottleManager(bottlesDirectory: bottles.bottlesDirectory)
        let persisted = try #require(reloaded.bottle(with: bottle.id))
        #expect(persisted.graphicsBackend == .dxmt)
        #expect(persisted.dxmtConfig.maxFrameRate == 120)
    }

    @Test
    func legacyDXMTBooleanMigratesToBackend() throws {
        let legacyJSON = """
        {"id": "\(UUID().uuidString)", "name": "Old", "windowsVersion": "win10",
         "createdAt": 700000000, "status": "ready", "games": [], "dxmtEnabled": true}
        """
        let bottle = try JSONDecoder().decode(Bottle.self, from: Data(legacyJSON.utf8))
        #expect(bottle.graphicsBackend == .dxmt)

        let legacyOff = legacyJSON.replacingOccurrences(of: "true", with: "false")
        let off = try JSONDecoder().decode(Bottle.self, from: Data(legacyOff.utf8))
        #expect(off.graphicsBackend == .off)
    }
}
