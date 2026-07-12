import Foundation
import Testing
@testable import Fable

/// The Memory Diet streaming-cap editor — pure, reversible, idempotent.
@Suite struct MemoryDietTests {

    @Test
    func poolSizeScalesWithUnifiedMemory() {
        #expect(MemoryDiet.recommendedPoolMB(forMemoryGB: 8) == 1536)
        #expect(MemoryDiet.recommendedPoolMB(forMemoryGB: 16) == 3072)
        #expect(MemoryDiet.recommendedPoolMB(forMemoryGB: 24) == 3072)  // the M4 Pro case
        #expect(MemoryDiet.recommendedPoolMB(forMemoryGB: 48) == 4096)
        #expect(MemoryDiet.recommendedPoolMB(forMemoryGB: 128) == 6144)
    }

    @Test
    func applyAddsAReadableBlockToAnEmptyFile() {
        let out = MemoryDiet.apply(to: "", poolMB: 3072)
        #expect(MemoryDiet.isApplied(out))
        #expect(MemoryDiet.appliedPoolMB(out) == 3072)
        #expect(out.contains("[SystemSettings]"))
        #expect(out.contains("r.Streaming.PoolSize=3072"))
        #expect(out.contains("r.Streaming.LimitPoolSizeToVRAM=0"))
    }

    @Test
    func applyPreservesTheGamesExistingConfigAndAppendsAtEnd() {
        let original = """
        [Core.System]
        Paths=../../../Engine/Content

        [/Script/Engine.RendererSettings]
        r.DefaultFeature.MotionBlur=False
        """
        let out = MemoryDiet.apply(to: original, poolMB: 3072)
        #expect(out.hasPrefix(original) || out.contains("r.DefaultFeature.MotionBlur=False"))
        #expect(out.contains("Paths=../../../Engine/Content"))
        // Our block is last, so it wins over any earlier [SystemSettings].
        #expect(out.range(of: "[Core.System]")!.lowerBound < out.range(of: MemoryDiet.beginMarker)!.lowerBound)
    }

    @Test
    func applyIsIdempotentAndReSizeable() {
        let once = MemoryDiet.apply(to: "[Core.System]\nPaths=x\n", poolMB: 3072)
        let twice = MemoryDiet.apply(to: once, poolMB: 3072)
        #expect(once == twice)  // applying again changes nothing
        // Exactly one managed block, ever.
        #expect(twice.components(separatedBy: MemoryDiet.beginMarker).count == 2)

        // Re-applying with a new size replaces, doesn't stack.
        let resized = MemoryDiet.apply(to: once, poolMB: 4096)
        #expect(MemoryDiet.appliedPoolMB(resized) == 4096)
        #expect(resized.components(separatedBy: MemoryDiet.beginMarker).count == 2)
    }

    @Test
    func removeRestoresTheOriginalExactly() {
        let original = "[Core.System]\nPaths=../../../Engine/Content\n"
        let dieted = MemoryDiet.apply(to: original, poolMB: 3072)
        #expect(MemoryDiet.remove(from: dieted) == original)
        // Remove is safe on a file that never had a block.
        #expect(MemoryDiet.remove(from: original) == original)
        #expect(!MemoryDiet.isApplied(MemoryDiet.remove(from: dieted)))
    }

    @Test
    func appliedPoolIgnoresTheGamesOwnPoolSizeLine() {
        // The game sets its own PoolSize outside our block — must not be read
        // as ours.
        let ini = "[SystemSettings]\nr.Streaming.PoolSize=1000\n"
        #expect(MemoryDiet.appliedPoolMB(ini) == nil)
        #expect(!MemoryDiet.isApplied(ini))
        let dieted = MemoryDiet.apply(to: ini, poolMB: 3072)
        #expect(MemoryDiet.appliedPoolMB(dieted) == 3072)  // reads OURS, not the 1000
    }
}

/// Finding the game's Engine.ini from a drive_c layout.
@Suite struct MemoryDietLocatorTests {
    private let fm = FileManager.default

    private func tempDriveC() throws -> URL {
        let dir = fm.temporaryDirectory.appending(path: "diet-\(UUID().uuidString)/drive_c", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Builds a realistic UE install + user config for `project`.
    private func plantUEGame(
        driveC: URL, installDir: String, project: String,
        platform: String = "Windows", user: String = "steamuser", writeConfig: Bool = true
    ) throws {
        let install = driveC.appending(path: installDir, directoryHint: .isDirectory)
        let win64 = install.appending(path: "\(project)/Binaries/Win64", directoryHint: .isDirectory)
        try fm.createDirectory(at: win64, withIntermediateDirectories: true)
        try Data().write(to: win64.appending(path: "\(project)-Win64-Shipping.exe"))
        if writeConfig {
            let cfg = driveC.appending(path: "users/\(user)/AppData/Local/\(project)/Saved/Config/\(platform)", directoryHint: .isDirectory)
            try fm.createDirectory(at: cfg, withIntermediateDirectories: true)
            try "[Core.System]\nPaths=x\n".write(to: cfg.appending(path: "Engine.ini"), atomically: true, encoding: .utf8)
        }
    }

    @Test
    func detectsUnrealProjectFromLauncherExe() throws {
        let driveC = try tempDriveC()
        defer { try? fm.removeItem(at: driveC.deletingLastPathComponent()) }
        // Launcher at the install root; shipping exe deeper — real RoN shape.
        try plantUEGame(driveC: driveC, installDir: "Games/Ready Or Not", project: "ReadyOrNot")
        try Data().write(to: driveC.appending(path: "Games/Ready Or Not/ReadyOrNot.exe"))

        #expect(MemoryDietLocator.unrealProjectName(driveC: driveC, executablePath: "Games/Ready Or Not/ReadyOrNot.exe") == "ReadyOrNot")
        let ini = MemoryDietLocator.engineINI(driveC: driveC, executablePath: "Games/Ready Or Not/ReadyOrNot.exe")
        #expect(ini?.path.hasSuffix("AppData/Local/ReadyOrNot/Saved/Config/Windows/Engine.ini") == true)
    }

    @Test
    func handlesUE4WindowsNoEditorAndBackslashPaths() throws {
        let driveC = try tempDriveC()
        defer { try? fm.removeItem(at: driveC.deletingLastPathComponent()) }
        try plantUEGame(driveC: driveC, installDir: "VotV", project: "VotV", platform: "WindowsNoEditor", user: "markoalagic")
        // Windows-style stored path.
        let ini = MemoryDietLocator.engineINI(driveC: driveC, executablePath: #"VotV\VotV.exe"#)
        #expect(ini?.lastPathComponent == "Engine.ini")
        #expect(ini?.path.contains("WindowsNoEditor") == true)
    }

    @Test
    func nonUnrealGameHasNoEngineINI() throws {
        let driveC = try tempDriveC()
        defer { try? fm.removeItem(at: driveC.deletingLastPathComponent()) }
        let dir = driveC.appending(path: "Balatro", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appending(path: "Balatro.exe"))
        #expect(MemoryDietLocator.unrealProjectName(driveC: driveC, executablePath: "Balatro/Balatro.exe") == nil)
        #expect(MemoryDietLocator.engineINI(driveC: driveC, executablePath: "Balatro/Balatro.exe") == nil)
    }

    @Test
    func returnsCreatePathWhenConfigDirExistsButFileDoesNot() throws {
        let driveC = try tempDriveC()
        defer { try? fm.removeItem(at: driveC.deletingLastPathComponent()) }
        try plantUEGame(driveC: driveC, installDir: "STALKER 2", project: "Stalker2", writeConfig: false)
        // Game ran once → LocalAppData folder exists, but no Engine.ini yet.
        let local = driveC.appending(path: "users/steamuser/AppData/Local/Stalker2", directoryHint: .isDirectory)
        try fm.createDirectory(at: local, withIntermediateDirectories: true)
        let ini = MemoryDietLocator.engineINI(driveC: driveC, executablePath: "STALKER 2/Stalker2.exe")
        #expect(ini?.path.hasSuffix("Local/Stalker2/Saved/Config/Windows/Engine.ini") == true)
    }

    // MARK: Advertised VRAM (the DXVK face of the diet)

    @Test
    func advertisedVRAMIsAQuarterOfUnifiedMemoryClamped() {
        #expect(MemoryDiet.advertisedVRAMMB(forMemoryGB: 8) == 2048)    // clamped floor
        #expect(MemoryDiet.advertisedVRAMMB(forMemoryGB: 16) == 4096)
        #expect(MemoryDiet.advertisedVRAMMB(forMemoryGB: 24) == 6144)
        #expect(MemoryDiet.advertisedVRAMMB(forMemoryGB: 32) == 8192)
        #expect(MemoryDiet.advertisedVRAMMB(forMemoryGB: 64) == 12288)  // clamped ceiling
        #expect(MemoryDiet.advertisedVRAMMB(forMemoryGB: 128) == 12288)
    }

    @Test
    func dxvkConfigCoversAllThreeReportPaths() {
        let conf = MemoryDiet.dxvkConfig(vramMB: 6144)
        #expect(conf.contains("dxgi.maxDeviceMemory = 6144"))
        #expect(conf.contains("dxgi.maxSharedMemory = 6144"))
        #expect(conf.contains("d3d9.maxAvailableMemory = 6144"))
    }

    @Test
    func ensureMemoryDietConfigWritesAndIsIdempotent() throws {
        let prefix = FileManager.default.temporaryDirectory
            .appending(path: "fable-dxvkconf-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: prefix, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: prefix) }

        let url = try DXVKManager.ensureMemoryDietConfig(at: prefix, vramMB: 4096)
        #expect(url.lastPathComponent == DXVKManager.memoryDietConfigName)
        let first = try String(contentsOf: url, encoding: .utf8)
        #expect(first.contains("dxgi.maxDeviceMemory = 4096"))

        // Re-run: same content, no error. Re-size: content follows.
        _ = try DXVKManager.ensureMemoryDietConfig(at: prefix, vramMB: 4096)
        #expect(try String(contentsOf: url, encoding: .utf8) == first)
        _ = try DXVKManager.ensureMemoryDietConfig(at: prefix, vramMB: 8192)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("dxgi.maxDeviceMemory = 8192"))
    }
}
